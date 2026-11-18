-- Plague Hulk: the crashed ship of Toxic_biters, a spawner that cannot move. Ten infected turrets of Toxic_biters
-- guard it (4 laser, 4 gun, 2 artillery). Every two minutes its boss biters (at most seven) march on the base, each with
-- a command of its own: a unit that joins a unit group is released from the spawner, which would build seven more.
-- With every sortie a cloud of spores reaches the three player turrets nearest to the hulk and shuts them down for 15
-- seconds. (Turning them to the enemy was tried and dropped: one turned rocket turret took out a quarter of a test base;
-- Toxic_biters already turns the turrets its biters kill.)

local cfg = require("lib.nb_data")
local util = require("scripts.nb_util")
local records = require("scripts.nb_records")
local spawn = require("scripts.nb_spawn")
local telegraph = require("scripts.nb_telegraph")

local M = {}

local UPKEEP_SECONDS = 5
local SORTIE_SECONDS = 120
local SPORE_TURRETS = 3
local SPORE_SECONDS = 15
local SPORE_RADIUS = 400
local SPORE_TELEGRAPH_SECONDS = 5

-- {prototype, dx, dy} from the hulk
local GUARDS = {
  { "tb_infected_laser_turret", -11, -7 },
  { "tb_infected_laser_turret", 11, -7 },
  { "tb_infected_laser_turret", -11, 8 },
  { "tb_infected_laser_turret", 11, 8 },
  { "tb_infected_gun_turret", -13, 0.5 },
  { "tb_infected_gun_turret", 13, 0.5 },
  { "tb_infected_gun_turret", -1, -8.5 },
  { "tb_infected_gun_turret", -1, 9.5 },
  { "tb_infected_artillery_turret", -16, -11 },
  { "tb_infected_artillery_turret", 16, 11 },
}

-- Magazines for the infected gun turrets, the best first. The item is picked by the ammo category of the gun:
-- Krastorio 2 moves the vanilla magazines to "kr-pistol".
local MAGAZINES = { "armor-piercing-rifle-magazine", "piercing-rounds-magazine", "rifle-magazine", "firearm-magazine" }

---@param turret LuaEntity
---@param count integer
local function insert_ammo(turret, count)
  local accepted = {}
  local parameters = turret.prototype.attack_parameters --[[@as AttackParameters]]
  for _, category in ipairs(parameters.ammo_categories or {}) do
    accepted[category] = true
  end
  for _, name in ipairs(MAGAZINES) do
    local item = prototypes.item[name]
    if item and item.ammo_category and accepted[item.ammo_category.name] then
      turret.insert({ name = name, count = count })
      return
    end
  end
  for name, item in pairs(prototypes.get_item_filtered({ { filter = "type", type = "ammo" } })) do
    local category = item.ammo_category
    if category and accepted[category.name] then
      turret.insert({ name = name, count = count })
      return
    end
  end
end

---@param turret LuaEntity
---@param initial boolean|nil
local function arm(turret, initial)
  if turret.type == "ammo-turret" then
    if turret.get_item_count() == 0 then
      insert_ammo(turret, 10)
    end
  elseif turret.type == "artillery-turret" then
    if initial then
      turret.insert({ name = "artillery-shell", count = 40 })
    end
  elseif turret.type == "electric-turret" then
    -- unpowered, the drain would empty the buffer
    turret.energy = turret.electric_buffer_size
  end
end

---@param summon NbSummon
---@param surface LuaSurface
---@return boolean ok
---@return string|nil message_key
function M.spawn(summon, surface)
  local position = spawn.find_position(summon, surface, cfg.HULK)
  local hulk = position and surface.create_entity({ name = cfg.HULK, position = position, force = "enemy" })
  if not hulk then
    return false, "msg-fail-position"
  end
  records.add(summon, hulk, true, "boss")
  local cx, cy = util.xy(hulk.position)
  for _, guard in ipairs(GUARDS) do
    -- Toxic_biters makes its infected turrets only while its startup setting tb-allow-infection is on
    local spot = prototypes.entity[guard[1]]
      and surface.find_non_colliding_position(guard[1], { cx + guard[2], cy + guard[3] }, 6, 0.5)
    local turret = spot and surface.create_entity({ name = guard[1], position = spot, force = "enemy" })
    if turret then
      arm(turret, true)
      records.add(summon, turret, false, "guard")
    end
  end
  surface.create_entity({ name = "big-demolisher-fissure-explosion", position = hulk.position })
  summon.hulk = { stunned = {} }
  return true, nil
end

---Selects the turrets that will be hit by the next spore release.
---@param surface LuaSurface
---@param summon NbSummon
---@param hulk LuaEntity
---@param count integer
---@return LuaEntity[]
local function spore_targets(surface, summon, hulk, count)
  local targets = {}
  local excluded = {}
  for _ = 1, count do
    local turret = spawn.nearest_target(surface, summon, hulk.position, SPORE_RADIUS,
      { types = cfg.TURRET_TYPES, exclude = excluded })
    if not turret then
      break
    end
    targets[#targets + 1] = turret
    if turret.unit_number then
      excluded[turret.unit_number] = true
    else
      break
    end
  end
  return targets
end

---Spores from the hulk: the marked, living turrets stop for a while.
---@param summon NbSummon
---@param surface LuaSurface
---@param force LuaForce
---@param turrets LuaEntity[]
local function release_spores(summon, surface, force, turrets)
  local until_tick = game.tick + SPORE_SECONDS * 60
  local stunned = 0
  local state = assert(summon.hulk)
  for index = 1, math.min(SPORE_TURRETS, #turrets) do
    local turret = turrets[index]
    if turret.valid and not turret.disabled_by_script then
      turret.disabled_by_script = true
      state.stunned[#state.stunned + 1] = { entity = turret, until_tick = until_tick }
      surface.create_entity({ name = "poison-cloud-visual-dummy", position = turret.position })
      stunned = stunned + 1
    end
  end
  if stunned > 0 then
    util.play(force, "hulk-spores")
    util.say(force, { "nexus-bosses.msg-hulk-spores", stunned, SPORE_SECONDS },
      util.COLORS.warning)
  end
end

---@param summon NbSummon
---@param all boolean wake every stunned turret, not only the ones whose time is up
local function wake(summon, all)
  local stunned = summon.hulk and summon.hulk.stunned or {}
  for index = #stunned, 1, -1 do
    local entry = stunned[index]
    if all or game.tick >= entry.until_tick then
      if entry.entity.valid then
        entry.entity.disabled_by_script = false
      end
      table.remove(stunned, index)
    end
  end
end

---@param summon NbSummon
---@param surface LuaSurface
---@param _force LuaForce
function M.tick(summon, surface, _force)
  wake(summon, false)
  local seconds = summon.active_seconds
  if seconds % UPKEEP_SECONDS == 0 then
    for _, guard in ipairs(records.of_role(summon, "guard")) do
      arm(guard.entity)
    end
  end
  local record = records.main(summon)
  local state = assert(summon.hulk)
  local interval = util.interval(summon, SORTIE_SECONDS)
  if record and interval then
    local sortie_due = util.due(state, "next_sortie", seconds, interval)
    local turret_count = math.floor(SPORE_TURRETS * (1 - (summon.weaken or 0)) + 0.5)
    if turret_count > 0 and state.next_sortie
      and state.spore_scheduled_for ~= state.next_sortie
      and seconds >= state.next_sortie - SPORE_TELEGRAPH_SECONDS then
      state.spore_scheduled_for = state.next_sortie
      local targets = spore_targets(surface, summon, record.entity, turret_count)
      local positions = {}
      for _, turret in ipairs(targets) do
        telegraph.filling_circle(summon, surface, turret, 2, SPORE_TELEGRAPH_SECONDS * 60)
        positions[#positions + 1] = util.copy_position(turret.position)
      end
      telegraph.queue(summon, "spores", SPORE_TELEGRAPH_SECONDS * 60, { positions = positions }, targets)
    end
    if sortie_due then
      spawn.send_spawner_units(summon, surface, record.entity)
      state.spore_scheduled_for = nil
    end
  end
end

---@param summon NbSummon
---@param surface LuaSurface
---@param force LuaForce
---@param entry NbPending
function M.on_pending(summon, surface, force, entry)
  if entry.kind == "spores" then
    local targets = {}
    for _, turret in ipairs(entry.entities or {}) do
      if turret.valid then
        targets[#targets + 1] = turret
      end
    end
    release_spores(summon, surface, force, targets)
  end
end

---@param summon NbSummon
---@return LocalisedString|nil
function M.status(summon)
  return { "nexus-bosses.status-hulk-guards", #records.of_role(summon, "guard") }
end

---@param summon NbSummon
function M.on_victory(summon)
  wake(summon, true)
  for _, guard in ipairs(records.of_role(summon, "guard")) do
    guard.entity.die()
  end
end

---@param summon NbSummon
function M.release(summon)
  wake(summon, true)
end

return M
