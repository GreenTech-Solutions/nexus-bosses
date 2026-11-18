-- The Watcher keeps its distance, marks nearby player buildings and sends electric drones to the base.

local cfg = require("lib.nb_data")
local util = require("scripts.nb_util")
local records = require("scripts.nb_records")
local spawn = require("scripts.nb_spawn")
local telegraph = require("scripts.nb_telegraph")
local spider = require("scripts.nb_spider")

local M = {}

local DRONE = "flying-electric-unit-3"
local DRONES = 6
local WAVE_SECONDS = 60
local MARK_SECONDS = 12
local MARK_RADIUS = 60
local TELEGRAPH_TICKS = 4 * 60
local APPROACH_SECONDS = 18
local APPROACH_RADIUS = 1500
local ROCKETS = 4
local AMMO = { { name = "flying-saucer-laser-ammo", count = 1 } }

---@param surface LuaSurface
---@param force LuaForce
---@param center MapPosition
---@param radius number
---@return LuaEntity|nil
local function nearest_building(surface, force, center, radius)
  local nearest, nearest_distance
  for _, entity in ipairs(surface.find_entities_filtered({ position = center, radius = radius, force = force })) do
    if entity.valid and entity.prototype.is_building then
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
---@return boolean ok
---@return string|nil message_key
function M.spawn(summon, surface)
  local position = spawn.find_position(summon, surface, cfg.WATCHER)
  local saucer = position and surface.create_entity({ name = cfg.WATCHER, position = position, force = "enemy" })
  if not saucer then
    return false, "msg-fail-position"
  end
  records.add(summon, saucer, true, "boss")
  local units = { saucer }
  for _ = 1, DRONES do
    local drone_position = util.offset(saucer.position, math.random() * 2 * math.pi, math.random() * 8)
    local drone = spawn.create_unit(surface, DRONE, drone_position)
    if drone then
      records.add(summon, drone, false, "escort")
      units[#units + 1] = drone
    end
  end
  spider.supply(saucer, AMMO)
  summon.watcher = {
    next_mark = util.interval(summon, MARK_SECONDS),
    last_wave = 0,
    last_approach = 0,
  }
  spawn.dispatch(surface, units, summon.position)
  return true, nil
end

---@param summon table
---@param surface LuaSurface
---@param _force LuaForce
function M.tick(summon, surface, _force)
  local boss = records.main(summon)
  if not boss then
    return
  end
  local saucer = boss.entity
  local state = summon.watcher
  local seconds = summon.active_seconds
  local drones = records.of_role(summon, "escort")
  if seconds - state.last_wave >= WAVE_SECONDS then
    state.last_wave = seconds
    while #drones < DRONES do
      local position = util.offset(saucer.position, math.random() * 2 * math.pi, math.random() * 8)
      local drone = spawn.create_unit(surface, DRONE, position)
      if not drone then
        break
      end
      records.add(summon, drone, false, "escort")
      drones[#drones + 1] = drone
    end
    spawn.dispatch(surface, drones, summon.position)
  end

  local mark_interval = util.interval(summon, MARK_SECONDS)
  if mark_interval and not state.next_mark then
    state.next_mark = (state.last_mark or 0) + mark_interval
  end
  if mark_interval and state.next_mark and seconds >= state.next_mark then
    state.next_mark = seconds + mark_interval
    local target = nearest_building(surface, game.forces[summon.force], saucer.position, MARK_RADIUS)
    if target and #drones > 0 then
      telegraph.line(surface, saucer, target, TELEGRAPH_TICKS)
      telegraph.circle(surface, target, 3, TELEGRAPH_TICKS)
      summon.pending[#summon.pending + 1] = {
        at = game.tick + TELEGRAPH_TICKS,
        kind = "strike",
        data = { target = target.unit_number, position = util.copy_position(target.position) },
      }
    end
  end

  if seconds - state.last_approach >= APPROACH_SECONDS then
    state.last_approach = seconds
    spider.supply(saucer, AMMO)
    local target = surface.find_nearest_enemy({
      position = summon.position,
      max_distance = APPROACH_RADIUS,
      force = "enemy",
    })
    if target then
      spider.approach(saucer, target)
    end
  end
end

---@param summon table
---@param surface LuaSurface
---@param _force LuaForce
---@param entry NbPending
function M.on_pending(summon, surface, _force, entry)
  if entry.kind ~= "strike" or #records.of_role(summon, "escort") == 0 then
    return
  end
  local target = entry.data.target and game.get_entity_by_unit_number(entry.data.target)
  if not (target and target.valid) then
    return
  end
  local source = records.main(summon)
  if not source then
    return
  end
  for _ = 1, ROCKETS do
    surface.create_entity({
      name = "explosive-rocket",
      position = source.entity.position,
      target = target,
      speed = 0.5,
      force = "enemy",
    })
  end
end

---@param summon table
---@return LocalisedString
function M.status(summon)
  local drones = #records.of_role(summon, "escort")
  for _, entry in ipairs(summon.pending or {}) do
    if entry.kind == "strike" then
      return { "nexus-bosses.status-watcher-marking" }
    end
  end
  if drones == 0 then
    return { "nexus-bosses.status-watcher-no-drones" }
  end
  return { "nexus-bosses.status-watcher-drones", drones }
end

return M
