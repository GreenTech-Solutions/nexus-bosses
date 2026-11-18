-- Shared helpers for the in-game FactorioTest tests.

local M = {}
local guards = require("scripts.nb_guards")

---Returns the Nexus surface, creating its chunks near the origin when needed.
---@return LuaSurface
function M.nexus()
  local surface = game.get_surface("nexus")
  if not surface then
    local planet = game.planets["nexus"]
    surface = planet.create_surface()
  end
  surface.request_to_generate_chunks({ 0, 0 }, 8)
  surface.force_generate_chunk_requests()
  return surface
end

---Resets the active summon and shortens the countdown for a headless test.
function M.reset()
  guards.reset()
  local state = remote.call("nexus-bosses", "get_state")
  local previous_position = state and state.summon and state.summon.beacon_position
  remote.call("nexus-bosses", "abort_summon", true)
  remote.call("nexus-bosses", "set_ignore_player_presence", true)
  remote.call("nexus-bosses", "set_countdown", 3)
  local surface = game.get_surface("nexus")
  if surface then
    -- Precursor waves and reinforcements from the previous test are not tracked and can destroy the next beacon.
    local centers = { { 0, 0 } }
    if previous_position then
      centers[#centers + 1] = previous_position
    end
    for _, center in ipairs(centers) do
      for _, force in ipairs({ "enemy", "player" }) do
        for _, entity in ipairs(surface.find_entities_filtered({ position = center, radius = 400, force = force })) do
          if entity.valid and entity.type ~= "character" then
            entity.destroy()
          end
        end
      end
    end
  end
end

---Creates a summon beacon on Nexus for the player force.
---@param boss_id string
---@param position MapPosition
---@param quality string|nil
---@return LuaEntity
function M.light(boss_id, position, quality)
  local parameters = {
    name = "nexus-summon-" .. boss_id,
    position = position,
    force = game.forces.player,
    raise_built = true,
  }
  if quality then
    parameters.quality = quality
  end
  local entity = M.nexus().create_entity(parameters)
  if not entity then
    error("could not create summon beacon for " .. boss_id)
  end
  return entity
end

---Returns the active summon snapshot from the remote interface.
---@return table|nil
function M.active()
  local state = remote.call("nexus-bosses", "get_state")
  return state and state.summon
end

---Describes the summon snapshot at a glance for a headless-test timeout.
---@param summon table|nil
---@return string
function M.describe_summon(summon)
  if not summon then
    return "no summon"
  end
  return string.format("phase=%s beacon_valid=%s spawn_note=%s", tostring(summon.phase), tostring(summon.beacon_valid),
    tostring(summon.spawn_note))
end

---@param summon table|nil
---@param role string
---@param name string|nil
---@return table|nil
function M.tracked(summon, role, name)
  for _, record in ipairs(summon and summon.tracked or {}) do
    if record.role == role and (not name or record.name == name) then
      return record
    end
  end
end

---@param summon table|nil
---@param kind string
---@return table|nil
function M.pending(summon, kind)
  for _, entry in ipairs(summon and summon.pending or {}) do
    if entry.kind == kind then
      return entry
    end
  end
end

---@param summon table|nil
---@param role string
---@return integer
function M.role_count(summon, role)
  local count = 0
  for _, record in ipairs(summon and summon.tracked or {}) do
    if record.role == role and not record.dead and not record.gone then
      count = count + 1
    end
  end
  return count
end

---@param surface LuaSurface
---@param name string
---@param position MapPosition|nil
---@param radius number|nil
---@return LuaEntity|nil
function M.find_entity(surface, name, position, radius)
  local filters = { name = name }
  if position then
    filters.position = position
    filters.radius = radius or 5
  end
  for _, entity in ipairs(surface.find_entities_filtered(filters)) do
    if entity.valid then
      return entity
    end
  end
end

---Waits for the active fight and steps it once per tick until the step returns true.
---@param timeout_ticks integer
---@param step fun(summon: table, ticks_since_active: integer): boolean|nil
function M.on_active(timeout_ticks, step)
  assert(timeout_ticks > 0, "timeout_ticks must be greater than zero")
  local elapsed = 0
  local active_ticks = 0
  local was_active = false
  local last_summon
  async(timeout_ticks)
  on_tick(function()
    elapsed = elapsed + 1
    local summon = M.active()
    last_summon = summon
    if summon and summon.phase == "active" then
      if not was_active then
        active_ticks = 0
        was_active = true
      end
      active_ticks = active_ticks + 1
      if step(summon, active_ticks) then
        done()
        return false
      end
    else
      was_active = false
      active_ticks = 0
    end
    if elapsed >= timeout_ticks then
      error("active fight step timed out: " .. M.describe_summon(last_summon))
    end
  end)
end

---Waits for the active summon to reach a phase, then calls the callback with its snapshot.
---@param phase string
---@param max_ticks integer
---@param callback fun(summon: table)
function M.wait_phase(phase, max_ticks, callback)
  assert(max_ticks > 0, "max_ticks must be greater than zero")
  local elapsed = 0
  async(max_ticks)
  on_tick(function()
    elapsed = elapsed + 1
    local summon = M.active()
    if summon and summon.phase == phase then
      callback(summon)
      done()
      return false
    end
    if elapsed >= max_ticks then
      error("summon did not reach phase " .. phase .. " within " .. max_ticks .. " ticks")
    end
  end)
end

return M
