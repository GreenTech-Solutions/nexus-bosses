-- Rogue Spidertron hunts nearby player power poles and disables surrounding buildings with an EMP.

local cfg = require("lib.nb_data")
local util = require("scripts.nb_util")
local records = require("scripts.nb_records")
local spawn = require("scripts.nb_spawn")
local telegraph = require("scripts.nb_telegraph")
local spider = require("scripts.nb_spider")

local M = {}

local SEARCH_RADIUS = 200
local APPROACH_STAND_OFF = 10
local EMP_RADIUS = 12
local EMP_TRIGGER_DISTANCE = 25
local EMP_TELEGRAPH_TICKS = 3 * 60
local EMP_DURATION_SECONDS = 15
local EMP_COOLDOWN_SECONDS = 20
local SUPPLY_SECONDS = 18
local AMMO = { { name = "explosive-rocket", count = 400 } }

---@param summon table
---@param surface LuaSurface
---@return boolean ok
---@return string|nil message_key
function M.spawn(summon, surface)
  local position = spawn.find_position(summon, surface, cfg.SPIDERTRON)
  local entity = position and surface.create_entity({ name = cfg.SPIDERTRON, position = position, force = "enemy" })
  if not entity then
    return false, "msg-fail-position"
  end
  records.add(summon, entity, true, "boss")
  spider.supply(entity, AMMO)
  summon.spidertron = { target = nil, exclude = {}, last_supply = 0, emp_ready = true }
  summon.emp = {}
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
  local entity = boss.entity
  local state = summon.spidertron
  local seconds = summon.active_seconds
  if seconds - state.last_supply >= SUPPLY_SECONDS then
    state.last_supply = seconds
    spider.supply(entity, AMMO)
  end

  state.exclude = state.exclude or {}
  for unit_number, until_tick in pairs(state.exclude) do
    if game.tick >= until_tick then
      state.exclude[unit_number] = nil
    end
  end

  local pole = state.target
  if not (pole and pole.valid) then
    pole = spawn.nearest_target(surface, summon, entity.position, SEARCH_RADIUS,
      { types = cfg.POLE_TYPES, exclude = state.exclude })
    state.target = pole
    if pole then
      telegraph.line(summon, surface, entity, pole, 18 * 60)
      spider.approach(entity, pole, APPROACH_STAND_OFF)
    end
  end
  if not pole then
    return
  end

  local weaken = summon.weaken or 0
  local emp_interval = weaken < 1 and util.interval(summon, EMP_COOLDOWN_SECONDS) or nil
  local emp_due = util.due(state, "next_emp", seconds, emp_interval)
  if emp_due then
    state.emp_ready = true
  end
  if not emp_interval then
    state.emp_ready = false
  end
  if state.emp_ready and pole and util.distance(entity.position, pole.position) <= EMP_TRIGGER_DISTANCE then
    state.emp_ready = false
    state.next_emp = nil
    local duration_ticks = math.floor(EMP_DURATION_SECONDS * (1 - weaken) * 60 + 0.5)
    local position = util.copy_position(pole.position)
    telegraph.circle(summon, surface, position, EMP_RADIUS, EMP_TELEGRAPH_TICKS)
    telegraph.queue(summon, "emp", EMP_TELEGRAPH_TICKS,
      { position = position, duration_ticks = duration_ticks })
  end
end

---@param summon table
---@param all boolean restore entries whose duration has not elapsed too
local function restore_emp(summon, all)
  local disabled_entities = summon.emp or {}
  for unit_number, disabled in pairs(disabled_entities) do
    if all or not disabled.until_tick or game.tick >= disabled.until_tick then
      local entity = disabled.entity
      if entity and entity.valid then
        entity.disabled_by_script = false
      end
      disabled_entities[unit_number] = nil
    end
  end
  summon.emp = disabled_entities
end

---@param summon table
---@param surface LuaSurface
---@param _force LuaForce
---@param entry NbPending
function M.on_pending(summon, surface, _force, entry)
  if entry.kind == "emp" then
    summon.emp = summon.emp or {}
    local state = summon.spidertron
    local duration_ticks = entry.data.duration_ticks or EMP_DURATION_SECONDS * 60
    local until_tick = game.tick + duration_ticks
    local position = entry.data.position
    if state then
      state.target = nil
      state.exclude = state.exclude or {}
      for _, pole in ipairs(surface.find_entities_filtered({
        position = position,
        radius = EMP_RADIUS,
        force = summon.force,
        type = cfg.POLE_TYPES,
      })) do
        if pole.unit_number then
          state.exclude[pole.unit_number] = until_tick
        end
      end
    end
    for _, entity in ipairs(surface.find_entities_filtered({
      position = position,
      radius = EMP_RADIUS,
      force = summon.force,
    })) do
      if entity.prototype.is_building and entity.is_updatable and entity.unit_number then
        local existing = summon.emp[entity.unit_number]
        if existing then
          existing.until_tick = math.max(existing.until_tick, until_tick)
        elseif entity.disabled_by_script == false then
          entity.disabled_by_script = true
          summon.emp[entity.unit_number] = { entity = entity, until_tick = until_tick }
        end
      end
    end
    if duration_ticks > 0 then
      telegraph.queue(summon, "emp_end", duration_ticks)
    else
      restore_emp(summon, false)
    end
  elseif entry.kind == "emp_end" then
    restore_emp(summon, false)
  end
end

---Restores any buildings this boss disabled.
---@param summon table
function M.restore(summon)
  restore_emp(summon, true)
end

---@param summon table
function M.release(summon)
  M.restore(summon)
end

---@param summon table
function M.on_victory(summon)
  M.restore(summon)
end

---@param summon table
---@return LocalisedString
function M.status(summon)
  local remaining = 0
  for _, disabled in pairs(summon.emp or {}) do
    local duration = math.floor(disabled.until_tick - game.tick)
    if duration > remaining then
      remaining = duration
    end
  end
  if remaining > 0 then
    return { "nexus-bosses.status-spidertron-emp", math.ceil(remaining / 60) }
  end
  return { "nexus-bosses.status-spidertron-approach" }
end

return M
