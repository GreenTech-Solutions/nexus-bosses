-- Last Commander: Big Monsters provides the unit prototype; this module spawns it, sends its escorts, and schedules
-- the reinforcements and optional atomic rocket.

local cfg = require("lib.nb_data")
local util = require("scripts.nb_util")
local records = require("scripts.nb_records")
local spawn = require("scripts.nb_spawn")
local telegraph = require("scripts.nb_telegraph")

local M = {}

local DROP_SECONDS = 45
local DROP_COUNT = 6
local DROP_MIN_DISTANCE = 15
local DROP_MAX_DISTANCE = 25
local DROP_RADIUS = 5
local DROP_WARNING_TICKS = 4 * 60
local NUKE_SECONDS = 90
local NUKE_RADIUS = 60
local NUKE_WARNING_RADIUS = 20
local NUKE_WARNING_TICKS = 5 * 60
local NUKE_SPEED = 0.4
local NUKE_SETTING = "bm-allow-nuker"
local NUKE_PROJECTILE = "mf-small-atomic-rocket"
local DROP_EXPLOSION = "big-explosion"
local DROP_UNIT = "bm_fake_human_machine_gunner_5"
local TURRET_TYPES = { ["ammo-turret"] = true, ["electric-turret"] = true, ["fluid-turret"] = true }

---@param summon table
---@param surface LuaSurface
---@return boolean ok
---@return string|nil message_key
function M.spawn(summon, surface)
  local position = spawn.find_position(summon, surface, cfg.COMMANDER)
  local commander = position and surface.create_entity({
    name = cfg.COMMANDER,
    position = position,
    force = "enemy",
  })
  if not commander then
    return false, "msg-fail-position"
  end
  records.add(summon, commander, true, "boss")
  local drop_interval = util.interval(summon, DROP_SECONDS)
  local weaken = summon.weaken or 0
  local nuke_interval = weaken == 0 and util.interval(summon, NUKE_SECONDS) or nil
  summon.commander = { next_drop = drop_interval, next_nuke = nuke_interval }
  spawn.dispatch(surface, { commander }, summon.position)
  return true, nil
end

---@return boolean
local function nuker_enabled()
  local setting = settings.global[NUKE_SETTING]
  return setting ~= nil and setting.value == true
end

---@param surface LuaSurface
---@param force LuaForce
---@param center MapPosition
---@return LuaEntity|nil
local function nearest_turret(surface, force, center)
  local nearest, nearest_distance
  for _, entity in ipairs(surface.find_entities_filtered({ position = center, radius = NUKE_RADIUS, force = force })) do
    if entity.valid and TURRET_TYPES[entity.type] then
      local distance = util.distance(center, entity.position)
      if not nearest_distance or distance < nearest_distance then
        nearest, nearest_distance = entity, distance
      end
    end
  end
  return nearest
end

---@param summon table
---@param surface LuaSurface
---@param boss LuaEntity
local function schedule_drop(summon, surface, boss, count)
  local boss_x, boss_y = util.xy(boss.position)
  local beacon_x, beacon_y = util.xy(summon.position)
  local angle = math.atan2(beacon_y - boss_y, beacon_x - boss_x)
  local distance = DROP_MIN_DISTANCE + math.random() * (DROP_MAX_DISTANCE - DROP_MIN_DISTANCE)
  local position = util.offset(boss.position, angle, distance)
  telegraph.circle(surface, position, DROP_RADIUS, DROP_WARNING_TICKS, summon)
  summon.pending[#summon.pending + 1] = {
    at = game.tick + DROP_WARNING_TICKS,
    kind = "drop",
    data = { position = util.copy_position(position), count = count },
  }
end

---@param summon table
---@param surface LuaSurface
---@param boss LuaEntity
---@param force LuaForce
local function schedule_nuke(summon, surface, boss, force)
  local turret = nearest_turret(surface, force, boss.position)
  local position = util.copy_position(turret and turret.position or summon.position)
  telegraph.circle(surface, turret or position, NUKE_WARNING_RADIUS, NUKE_WARNING_TICKS, summon)
  summon.pending[#summon.pending + 1] = {
    at = game.tick + NUKE_WARNING_TICKS,
    kind = "nuke",
    data = { position = position },
  }
end

---@param summon table
---@param surface LuaSurface
---@param position MapPosition
---@param count integer
local function spawn_drop(summon, surface, position, count)
  surface.create_entity({ name = DROP_EXPLOSION, position = position, force = "enemy" })
  local units = {}
  for _ = 1, count do
    local spot = surface.find_non_colliding_position(DROP_UNIT, position, DROP_RADIUS, 1)
    local unit = spot and spawn.create_unit(surface, DROP_UNIT, spot)
    if unit then
      records.add(summon, unit, false, "escort")
      units[#units + 1] = unit
    end
  end
  spawn.dispatch(surface, units, summon.position)
end

---@param summon table
---@param surface LuaSurface
---@param _force LuaForce
---@param entry NbPending
function M.on_pending(summon, surface, _force, entry)
  if entry.kind == "drop" then
    spawn_drop(summon, surface, entry.data.position, entry.data.count or DROP_COUNT)
  elseif entry.kind == "nuke" and nuker_enabled() then
    local boss = records.main(summon)
    if boss then
      surface.create_entity({
        name = NUKE_PROJECTILE,
        position = boss.entity.position,
        target = entry.data.position,
        speed = NUKE_SPEED,
        force = "enemy",
      })
    end
  end
end

---@param summon table
---@param surface LuaSurface
---@param force LuaForce
function M.tick(summon, surface, force)
  local record = records.main(summon)
  if not record then
    return
  end

  if summon.active_seconds % spawn.REDISPATCH_SECONDS == 0 then
    spawn.redispatch(summon, surface, records.commandable_units(summon))
  end

  local state = summon.commander
  local weaken = summon.weaken or 0
  local drop_interval = util.interval(summon, DROP_SECONDS)
  if drop_interval and state.next_drop and summon.active_seconds >= state.next_drop then
    local drop_count = math.floor(DROP_COUNT * (1 - weaken) + 0.5)
    if drop_count > 0 then
      schedule_drop(summon, surface, record.entity, drop_count)
    end
    state.next_drop = summon.active_seconds + drop_interval
  end

  if nuker_enabled() and weaken == 0 then
    local nuke_interval = util.interval(summon, NUKE_SECONDS)
    if nuke_interval then
      state.next_nuke = state.next_nuke or summon.active_seconds + nuke_interval
    end
    if nuke_interval and state.next_nuke and summon.active_seconds >= state.next_nuke then
      state.next_nuke = summon.active_seconds + nuke_interval
      schedule_nuke(summon, surface, record.entity, force)
    end
  else
    state.next_nuke = nil
  end
end

---@param summon table
---@return LocalisedString|nil
function M.status(summon)
  local state = summon.commander
  local drop_remaining = state.next_drop and math.max(0, state.next_drop - summon.active_seconds) or nil
  local nuke_remaining = state.next_nuke and math.max(0, state.next_nuke - summon.active_seconds) or nil
  for _, entry in ipairs(summon.pending or {}) do
    local remaining = math.max(0, math.ceil((entry.at - game.tick) / 60))
    if entry.kind == "drop" then
      drop_remaining = remaining
    elseif entry.kind == "nuke" then
      nuke_remaining = remaining
    end
  end
  if not drop_remaining then
    return nil
  end
  if nuker_enabled() and nuke_remaining then
    return { "nexus-bosses.status-commander-both", drop_remaining, nuke_remaining }
  end
  return { "nexus-bosses.status-commander-drop", drop_remaining }
end

return M
