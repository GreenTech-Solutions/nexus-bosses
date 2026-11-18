-- The Watcher keeps its distance, marks nearby player buildings and sends electric drones to the base.

local cfg = require("lib.nb_data")
local util = require("scripts.nb_util")
local records = require("scripts.nb_records")
local spawn = require("scripts.nb_spawn")
local telegraph = require("scripts.nb_telegraph")
local spider = require("scripts.nb_spider")

local M = {}

local DRONE = cfg.WATCHER_DRONE
local DRONES = 6
local WAVE_SECONDS = 60
local MARK_SECONDS = 12
local MARK_RADIUS = 60
local TELEGRAPH_TICKS = 4 * 60
local APPROACH_SECONDS = 18
local ROCKETS = 4
local AMMO = { { name = cfg.WATCHER_AMMO, count = 1 } }

---@param summon NbSummon
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
    last_wave = 0,
    last_approach = 0,
  }
  spawn.dispatch(surface, units, summon.position)
  return true, nil
end

---@param summon NbSummon
---@param surface LuaSurface
---@param _force LuaForce
function M.tick(summon, surface, _force)
  local boss = records.main(summon)
  if not boss then
    return
  end
  local saucer = boss.entity
  local state = assert(summon.watcher)
  local seconds = summon.active_seconds
  local drone_records = records.of_role(summon, "escort")
  local drone_count = #drone_records
  local drones = {}
  for _, record in ipairs(drone_records) do
    drones[#drones + 1] = record.entity
  end
  if seconds - state.last_wave >= WAVE_SECONDS then
    state.last_wave = seconds
    while drone_count < DRONES do
      local position = util.offset(saucer.position, math.random() * 2 * math.pi, math.random() * 8)
      local drone = spawn.create_unit(surface, DRONE, position)
      if not drone then
        break
      end
      records.add(summon, drone, false, "escort")
      drones[#drones + 1] = drone
      drone_count = drone_count + 1
    end
    spawn.dispatch(surface, drones, summon.position)
  end

  local mark_interval = util.interval(summon, MARK_SECONDS, true)
  if util.due(state, "next_mark", seconds, mark_interval) and drone_count > 0 then
    local target = spawn.nearest_target(surface, summon, saucer.position, MARK_RADIUS, { building = true })
    if target then
      telegraph.line(summon, surface, saucer, target, TELEGRAPH_TICKS)
      telegraph.circle(summon, surface, target, 3, TELEGRAPH_TICKS)
      telegraph.queue(summon, "strike", TELEGRAPH_TICKS,
        { target = target.unit_number, position = util.copy_position(target.position) }, { target })
    end
  end

  if seconds - state.last_approach >= APPROACH_SECONDS then
    state.last_approach = seconds
    spider.supply(saucer, AMMO)
    local target = surface.find_nearest_enemy({
      position = summon.position,
      max_distance = cfg.DEFENCE_RADIUS,
      force = "enemy",
    })
    if target then
      spider.approach(saucer, target)
    end
  end
end

---@param summon NbSummon
---@param surface LuaSurface
---@param _force LuaForce
---@param entry NbPending
function M.on_pending(summon, surface, _force, entry)
  if entry.kind ~= "strike" or #records.of_role(summon, "escort") == 0 then
    return
  end
  local target = entry.entities and entry.entities[1]
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

---@param summon NbSummon
---@return LocalisedString
function M.status(summon)
  local drones = #records.of_role(summon, "escort")
  local state = assert(summon.watcher)
  for _, entry in ipairs(summon.pending or {}) do
    if entry.kind == "strike" then
      return { "nexus-bosses.status-watcher-marking" }
    end
  end
  if drones == 0 then
    return { "nexus-bosses.status-watcher-no-drones" }
  end
  local interval = util.interval(summon, MARK_SECONDS, true)
  local next_mark = state.next_mark or (summon.active_seconds + (interval or 0))
  local remaining = math.max(0, math.ceil(next_mark - summon.active_seconds))
  return { "nexus-bosses.status-watcher-drones-next", drones, remaining }
end

return M
