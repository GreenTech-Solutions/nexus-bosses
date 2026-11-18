-- The Colossus is one of six Big Monsters units copied under Nexus Bosses' names. Each variant has its own attack.

local cfg = require("lib.nb_data")
local util = require("scripts.nb_util")
local records = require("scripts.nb_records")
local spawn = require("scripts.nb_spawn")
local telegraph = require("scripts.nb_telegraph")

local M = {}

local INTERVALS = {
  fire = 4,
  storm = 3,
  armored = 40,
  mother = 20,
  ["fire-spitter"] = 15,
  ["acid-spitter"] = 15,
}
local TELEGRAPH_SECONDS = {
  fire = 1,
  storm = 1,
  armored = 3,
  mother = 3,
  ["fire-spitter"] = 2,
  ["acid-spitter"] = 2,
}
local SHIELD_SECONDS = 10
local SPITTER_RADIUS = 40
local SPITTER_ATTACK_RADIUS = 6
local SPITTER_SHOTS = 5
local MOTHER_ESCORTS = 6
local SPITTER_PROJECTILES = {
  ["fire-spitter"] = cfg.COLOSSUS_FIRE_PROJECTILE,
  ["acid-spitter"] = cfg.COLOSSUS_ACID_PROJECTILE,
}

---@param summon table
---@param surface LuaSurface
---@return boolean ok
---@return string|nil message_key
function M.spawn(summon, surface)
  local position = spawn.find_position(summon, surface, summon.variant_entity)
  local boss = position and surface.create_entity({
    name = summon.variant_entity,
    position = position,
    force = "enemy",
  })
  if not boss then
    return false, "msg-fail-position"
  end
  records.add(summon, boss, true, "boss")
  summon.colossus = {}
  spawn.dispatch(surface, { boss }, summon.position)
  return true, nil
end

---@param summon table
---@param surface LuaSurface
---@param boss LuaEntity
local function schedule_attack(summon, surface, boss)
  local variant = summon.variant
  local warning = TELEGRAPH_SECONDS[variant] * 60
  local data = {}
  local kind = "colossus-" .. variant

  if variant == "fire" then
    local point = util.offset(boss.position, math.random() * 2 * math.pi, math.random() * 5)
    telegraph.filling_circle(summon, surface, point, 3, warning)
    data.position = util.copy_position(point)
  elseif variant == "storm" then
    telegraph.ring(summon, surface, boss, 6, warning)
  elseif variant == "armored" then
    telegraph.ring(summon, surface, boss, 8, warning)
  elseif variant == "mother" then
    local boss_x, boss_y = util.xy(boss.position)
    local beacon_x, beacon_y = util.xy(summon.position)
    local angle = math.atan2(beacon_y - boss_y, beacon_x - boss_x)
    local point = util.offset(boss.position, angle, 10)
    telegraph.filling_circle(summon, surface, point, 4, warning)
    data.position = util.copy_position(point)
  elseif variant == "fire-spitter" or variant == "acid-spitter" then
    local turret = spawn.nearest_target(surface, summon, boss.position, SPITTER_RADIUS,
      { types = cfg.TURRET_TYPES })
    if not turret then
      return
    end
    data.position = util.copy_position(turret.position)
    telegraph.filling_circle(summon, surface, data.position, SPITTER_ATTACK_RADIUS, warning)
  end

  telegraph.queue(summon, kind, warning, data)
end

---@param summon table
---@param surface LuaSurface
---@param position MapPosition
local function spawn_mother_escort(summon, surface, position)
  local units = {}
  for _ = 1, MOTHER_ESCORTS do
    local spot = surface.find_non_colliding_position("behemoth-biter", position, 8, 1)
    local unit = spot and spawn.create_unit(surface, "behemoth-biter", spot)
    if unit then
      records.add(summon, unit, false, "escort")
      units[#units + 1] = unit
    end
  end
  spawn.dispatch(surface, units, summon.position)
end

---@param summon table
---@param surface LuaSurface
---@param entry NbPending
function M.on_pending(summon, surface, _force, entry)
  local boss = records.main(summon)
  if not boss then
    return
  end

  if entry.kind == "colossus-fire" then
    local point = entry.data.position
    surface.create_entity({
      name = cfg.COLOSSUS_FIRE_PROJECTILE,
      position = point,
      target_position = point,
      source = boss.entity,
      force = "enemy",
      speed = 1,
    })
  elseif entry.kind == "colossus-storm" then
    surface.create_entity({ name = cfg.COLOSSUS_STORM_EXPLOSION, position = boss.entity.position, force = "enemy" })
  elseif entry.kind == "colossus-armored" then
    summon.shield = { health = boss.entity.health, until_tick = game.tick + SHIELD_SECONDS * 60 }
    telegraph.ring(summon, surface, boss.entity, 8, SHIELD_SECONDS * 60)
  elseif entry.kind == "colossus-mother" then
    spawn_mother_escort(summon, surface, entry.data.position)
  elseif entry.kind == "colossus-fire-spitter" or entry.kind == "colossus-acid-spitter" then
    local projectile = SPITTER_PROJECTILES[summon.variant]
    local center = entry.data.position
    for _ = 1, SPITTER_SHOTS do
      local target = util.offset(center, math.random() * 2 * math.pi, math.random() * SPITTER_ATTACK_RADIUS)
      surface.create_entity({
        name = projectile,
        position = boss.entity.position,
        target_position = target,
        source = boss.entity,
        force = "enemy",
        speed = 1,
      })
    end
  end
end

---@param summon table
---@param surface LuaSurface
---@param _force LuaForce
function M.tick(summon, surface, _force)
  local record = records.main(summon)
  if not record then
    return
  end
  local boss = record.entity
  local seconds = summon.active_seconds

  if seconds % spawn.REDISPATCH_SECONDS == 0 then
    spawn.redispatch(summon, surface, records.commandable_units(summon))
  end

  local shield = summon.shield
  if shield then
    if game.tick < shield.until_tick then
      if boss.health < shield.health then
        boss.health = shield.health
      end
    else
      summon.shield = nil
    end
  end

  local state = summon.colossus
  local interval = util.interval(summon, INTERVALS[summon.variant], true)
  if util.due(state, "next_attack", seconds, interval) then
    schedule_attack(summon, surface, boss)
  end
end

---@param summon table
---@return LocalisedString|nil
function M.status(summon)
  local shield = summon.shield
  if shield and game.tick < shield.until_tick then
    return { "nexus-bosses.status-colossus-shield", math.ceil((shield.until_tick - game.tick) / 60) }
  end

  for _, entry in ipairs(summon.pending or {}) do
    if entry.kind:find("^colossus%-") then
      local remaining = math.max(0, math.ceil((entry.at - game.tick) / 60))
      return {
        "nexus-bosses.status-colossus-attack",
        { "nexus-bosses.colossus-attack-" .. summon.variant },
        remaining,
      }
    end
  end

  local interval = util.interval(summon, INTERVALS[summon.variant], true)
  if not interval then
    return nil
  end
  local next_attack = summon.colossus.next_attack
  if not next_attack then
    return { "nexus-bosses.status-colossus-attack", { "nexus-bosses.colossus-attack-" .. summon.variant },
      math.ceil(interval) }
  end
  local remaining = math.max(0, math.ceil(next_attack - summon.active_seconds))
  return {
    "nexus-bosses.status-colossus-attack",
    { "nexus-bosses.colossus-attack-" .. summon.variant },
    remaining,
  }
end

return M
