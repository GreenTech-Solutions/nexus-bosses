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

---@param surface LuaSurface
---@param position MapPosition
---@param force LuaForce
---@return LuaEntity|nil
local function nearest_pole(surface, position, force)
  local nearest, nearest_distance
  for _, pole in ipairs(surface.find_entities_filtered({
    position = position,
    radius = SEARCH_RADIUS,
    force = force,
    type = "electric-pole",
  })) do
    local distance = util.distance(position, pole.position)
    if not nearest_distance or distance < nearest_distance then
      nearest, nearest_distance = pole, distance
    end
  end
  return nearest
end

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
  summon.spidertron = { last_target = nil, next_emp = 0, last_supply = 0 }
  summon.emp = {}
  return true, nil
end

---@param summon table
---@param surface LuaSurface
---@param force LuaForce
function M.tick(summon, surface, force)
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

  local pole = nearest_pole(surface, entity.position, force)
  if not pole then
    state.last_target = nil
    return
  end
  if state.last_target ~= pole.unit_number then
    local route = telegraph.line(surface, entity, pole, 18 * 60)
    summon.renders[#summon.renders + 1] = { render = route }
    spider.approach(entity, pole, APPROACH_STAND_OFF)
    state.last_target = pole.unit_number
  end

  local emp_interval = util.interval(summon, EMP_COOLDOWN_SECONDS)
  if emp_interval and not state.next_emp then
    state.next_emp = math.max(0, (state.last_emp or 0) + emp_interval)
  end
  if emp_interval and seconds >= state.next_emp and util.distance(entity.position, pole.position) <= EMP_TRIGGER_DISTANCE then
    state.next_emp = seconds + emp_interval
    local duration_ticks = math.floor(EMP_DURATION_SECONDS * (1 - (summon.weaken or 0)) * 60 + 0.5)
    telegraph.ring(surface, pole, EMP_RADIUS, EMP_TELEGRAPH_TICKS)
    summon.pending[#summon.pending + 1] = {
      at = game.tick + EMP_TELEGRAPH_TICKS,
      kind = "emp",
      data = { position = util.copy_position(pole.position), duration_ticks = duration_ticks },
    }
  end
end

---@param summon table
---@param all boolean restore entries whose duration has not elapsed too
local function restore_emp(summon, all)
  local disabled_entities = summon.emp or {}
  for index = #disabled_entities, 1, -1 do
    local disabled = disabled_entities[index]
    if all or not disabled.until_tick or game.tick >= disabled.until_tick then
      local entity = disabled.entity
      if entity and entity.valid then
        entity.disabled_by_script = false
      end
      table.remove(disabled_entities, index)
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
    local duration_ticks = entry.data.duration_ticks or EMP_DURATION_SECONDS * 60
    local until_tick = game.tick + duration_ticks
    for _, entity in ipairs(surface.find_entities_filtered({
      position = entry.data.position,
      radius = EMP_RADIUS,
      force = summon.force,
    })) do
      if entity.prototype.is_building then
        local existing
        for _, disabled in ipairs(summon.emp) do
          if disabled.entity == entity then
            existing = disabled
            break
          end
        end
        if existing then
          existing.until_tick = math.max(existing.until_tick, until_tick)
        elseif entity.disabled_by_script == false then
          entity.disabled_by_script = true
          summon.emp[#summon.emp + 1] = { entity = entity, until_tick = until_tick }
        end
      end
    end
    if duration_ticks > 0 then
      summon.pending[#summon.pending + 1] = { at = game.tick + duration_ticks, kind = "emp_end", data = {} }
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
  for _, disabled in ipairs(summon.emp or {}) do
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
