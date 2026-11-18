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
local NUKE_PROJECTILE = cfg.COMMANDER_NUKE
local DROP_EXPLOSION = cfg.COMMANDER_DROP_EXPLOSION
local DROP_UNIT = cfg.COMMANDER_DROP_UNIT

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
  summon.commander = {}
  spawn.dispatch(surface, { commander }, summon.position)
  return true, nil
end

---@return boolean
local function nuker_enabled()
  local setting = settings.global[NUKE_SETTING]
  return setting ~= nil and setting.value == true
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
  telegraph.circle(summon, surface, position, DROP_RADIUS, DROP_WARNING_TICKS)
  telegraph.queue(summon, "drop", DROP_WARNING_TICKS, { position = util.copy_position(position), count = count })
end

---@param summon table
---@param surface LuaSurface
---@param boss LuaEntity
local function schedule_nuke(summon, surface, boss)
  local turret = spawn.nearest_target(surface, summon, boss.position, NUKE_RADIUS, { types = cfg.TURRET_TYPES })
  local position = util.copy_position(turret and turret.position or summon.position)
  telegraph.circle(summon, surface, position, NUKE_WARNING_RADIUS, NUKE_WARNING_TICKS)
  telegraph.queue(summon, "nuke", NUKE_WARNING_TICKS, { position = position })
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
---@param _force LuaForce
function M.tick(summon, surface, _force)
  local record = records.main(summon)
  if not record then
    return
  end

  if summon.active_seconds % spawn.REDISPATCH_SECONDS == 0 then
    spawn.redispatch(summon, surface, records.commandable_units(summon))
  end

  local state = summon.commander
  local seconds = summon.active_seconds
  local drop_due = util.due(state, "next_drop", seconds, util.interval(summon, DROP_SECONDS))
  if drop_due then
    local weaken = summon.weaken or 0
    local drop_count = math.floor(DROP_COUNT * (1 - weaken) + 0.5)
    if drop_count > 0 then
      schedule_drop(summon, surface, record.entity, drop_count)
    end
  end

  local nuke_allowed = nuker_enabled() and (summon.weaken or 0) == 0
  local nuke_interval = nuke_allowed and util.interval(summon, NUKE_SECONDS) or nil
  if util.due(state, "next_nuke", seconds, nuke_interval) then
    schedule_nuke(summon, surface, record.entity)
  end
end

---@param summon table
---@return LocalisedString|nil
function M.status(summon)
  local state = summon.commander
  local drop_remaining = state.next_drop and math.ceil(math.max(0, state.next_drop - summon.active_seconds)) or nil
  local nuke_remaining = state.next_nuke and math.ceil(math.max(0, state.next_nuke - summon.active_seconds)) or nil
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
