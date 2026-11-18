-- Shared helpers for the in-game FactorioTest tests.

local M = {}

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
  remote.call("nexus-bosses", "abort_summon", true)
  remote.call("nexus-bosses", "set_ignore_player_presence", true)
  remote.call("nexus-bosses", "set_countdown", 3)
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
