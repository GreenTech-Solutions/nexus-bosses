-- Plague Hulk: the crashed ship of Toxic_biters, a spawner that cannot move. Ten infected turrets of Toxic_biters
-- guard it (4 laser, 4 gun, 2 artillery). Every two minutes it sends a sortie of up to seven boss biters at the base,
-- combining its own units with biters it creates when needed. A sortie's spore cloud follows its units: when one first
-- approaches player turrets, it marks a 15-tile circle around that unit and shuts down turrets in it after three
-- seconds. (Turning them to the enemy was tried and dropped: one turned rocket turret took out a quarter of a test
-- base; Toxic_biters already turns the turrets its biters kill.)

local cfg = require("lib.nb_data")
local util = require("scripts.nb_util")
local records = require("scripts.nb_records")
local spawn = require("scripts.nb_spawn")
local telegraph = require("scripts.nb_telegraph")

local M = {}

local UPKEEP_SECONDS = 5
local SORTIE_SECONDS = 120
local SORTIE_UNITS = 7
local SORTIE_MIN_RADIUS = 6
local SORTIE_MAX_RADIUS = 12
local SORTIE_POSITION_ATTEMPTS = 24
local SPORE_TRIGGER = 30
local SPORE_SECONDS = 15
local SPORE_RADIUS = 15
local SPORE_TELEGRAPH_TICKS = 3 * 60

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
  summon.hulk = { stunned = {}, squad = nil }
  return true, nil
end

---Spores from the hulk: the turrets in the marked circle stop for a while.
---@param summon NbSummon
---@param surface LuaSurface
---@param force LuaForce
---@param position MapPosition
---@param duration_ticks integer
local function release_spores(summon, surface, force, position, duration_ticks)
  local until_tick = game.tick + duration_ticks
  local stunned = 0
  local state = assert(summon.hulk)
  for _, turret in ipairs(surface.find_entities_filtered({
    position = position,
    radius = SPORE_RADIUS,
    force = summon.force,
    type = cfg.TURRET_TYPES,
  })) do
    if turret.valid and not turret.disabled_by_script then
      turret.disabled_by_script = true
      state.stunned[#state.stunned + 1] = { entity = turret, until_tick = until_tick }
      surface.create_entity({ name = "poison-cloud-visual-dummy", position = turret.position })
      stunned = stunned + 1
    end
  end
  if stunned > 0 then
    util.play(force, "hulk-spores")
    util.say(force, { "nexus-bosses.msg-hulk-spores", stunned, math.ceil(duration_ticks / 60) }, util.COLORS.warning)
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

---@param surface LuaSurface
---@param spawner LuaEntity
---@param name string
---@return LuaEntity|nil
local function create_sortie_unit(surface, spawner, name)
  for _ = 1, SORTIE_POSITION_ATTEMPTS do
    local angle = math.random() * 2 * math.pi
    local radius = SORTIE_MIN_RADIUS + math.random() * (SORTIE_MAX_RADIUS - SORTIE_MIN_RADIUS)
    local wanted = util.offset(spawner.position, angle, radius)
    local position = surface.find_non_colliding_position(name, wanted, 1, 0.5)
    if position then
      local distance = util.distance(spawner.position, position)
      if distance >= SORTIE_MIN_RADIUS and distance <= SORTIE_MAX_RADIUS then
        local unit = spawn.create_unit(surface, name, position)
        if unit then
          return unit
        end
      end
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
    if sortie_due then
      local units = {}
      for _, unit in ipairs(record.entity.units) do
        if unit.valid then
          units[#units + 1] = unit
        end
      end
      local missing = math.max(0, SORTIE_UNITS - #units)
      local available_escorts = math.max(0, cfg.ESCORT_CAP - #records.of_role(summon, "escort"))
      local precursors = cfg.BOSSES["plague-hulk"].precursors
      local destination_target = spawn.nearest_building(surface, record.entity.position, summon)
      local destination = destination_target and destination_target.position or summon.position
      for _ = 1, math.min(missing, available_escorts) do
        local name = precursors[math.random(#precursors)]
        local unit = create_sortie_unit(surface, record.entity, name)
        if unit then
          records.add(summon, unit, false, "escort")
          units[#units + 1] = unit
          local commandable = unit.commandable --[[@as LuaCommandable]]
          commandable.set_command(spawn.attack_command(destination))
        end
      end
      spawn.send_spawner_units(summon, surface, record.entity)
      state.squad = { units = units, spored = false }
    end

    local squad = state.squad
    if squad and not squad.spored then
      for _, unit in ipairs(squad.units) do
        if unit.valid and spawn.nearest_target(surface, summon, unit.position, SPORE_TRIGGER,
          { types = cfg.TURRET_TYPES }) then
          squad.spored = true
          local weaken = summon.weaken or 0
          if weaken < 1 then
            local position = util.copy_position(unit.position)
            local duration_ticks = math.floor(SPORE_SECONDS * (1 - weaken) * 60 + 0.5)
            telegraph.filling_circle(summon, surface, position, SPORE_RADIUS, SPORE_TELEGRAPH_TICKS)
            telegraph.queue(summon, "spores", SPORE_TELEGRAPH_TICKS,
              { position = position, duration_ticks = duration_ticks })
          end
          break
        end
      end
    end
  end
end

---@param summon NbSummon
---@param surface LuaSurface
---@param force LuaForce
---@param entry NbPending
function M.on_pending(summon, surface, force, entry)
  if entry.kind == "spores" then
    release_spores(summon, surface, force, entry.data.position,
      entry.data.duration_ticks or SPORE_SECONDS * 60)
  end
end

---@param summon NbSummon
---@return LocalisedString|nil
function M.status(summon)
  local state = assert(summon.hulk)
  local squad = state.squad
  if squad and not squad.spored then
    local living = 0
    for _, unit in ipairs(squad.units) do
      if unit.valid then
        living = living + 1
      end
    end
    if living > 0 then
      return { "nexus-bosses.status-hulk-squad", living }
    end
  end
  local interval = util.interval(summon, SORTIE_SECONDS)
  local next_sortie = state.next_sortie or (summon.active_seconds + (interval or 0))
  return {
    "nexus-bosses.status-hulk-next",
    #records.of_role(summon, "guard"),
    math.max(0, math.ceil(next_sortie - summon.active_seconds)),
  }
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
