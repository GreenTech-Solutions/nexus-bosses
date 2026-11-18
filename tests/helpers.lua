-- Shared helpers for the in-game FactorioTest tests.

local M = {}
local cfg = require("lib.nb_data")
local guards = require("scripts.nb_guards")
local util = require("scripts.nb_util")
---@type LuaEntity[]
local test_defences = {}
---@type table<integer, {position: MapPosition, surface: LuaSurface}>
local displaced_players = {}

---Restores players moved out of a test's defence radius.
function M.restore_players()
  for player_index, previous in pairs(displaced_players) do
    local player = game.get_player(player_index)
    local character = player and player.character
    if character and character.valid then
      character.teleport(previous.position, previous.surface)
    end
  end
  displaced_players = {}
end

---Moves player characters outside a test's defence radius and restores them on reset.
---@param position MapPosition
---@param radius number
function M.move_players_away(position, radius)
  local surface = M.nexus()
  for _, player in pairs(game.forces.player.players) do
    local character = player.character
    if character and character.valid and character.surface_index == surface.index then
      local character_x, character_y = util.xy(character.position)
      local position_x, position_y = util.xy(position)
      local dx = character_x - position_x
      local dy = character_y - position_y
      if dx * dx + dy * dy <= radius * radius then
        displaced_players[player.index] = { position = character.position, surface = character.surface }
        character.teleport({ x = position_x + 10000, y = position_y + 10000 }, surface)
      end
    end
  end
end

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
  M.restore_players()
  guards.reset()
  local state = remote.call("nexus-bosses", "get_state")
  local previous_position = state and state.summon and state.summon.beacon_position
  remote.call("nexus-bosses", "abort_summon", true)
  remote.call("nexus-bosses", "set_ignore_player_presence", true)
  remote.call("nexus-bosses", "set_countdown", 3)
  for _, entity in ipairs(test_defences) do
    if entity.valid then
      entity.destroy()
    end
  end
  test_defences = {}
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

---Creates an empty, indestructible team turret to keep a long test fight defended.
---@param position MapPosition|nil exact position, or a position off the boss approach route
---@return LuaEntity
function M.defend(position)
  local surface = M.nexus()
  if not position then
    local summon = M.active()
    assert(summon and summon.beacon_position and summon.angle, "a summon is needed to place test defence")
    local angle = summon.angle + math.pi / 2
    local radius = cfg.DEFENCE_RADIUS - 20
    position = {
      x = summon.beacon_position.x + math.cos(angle) * radius,
      y = summon.beacon_position.y + math.sin(angle) * radius,
    }
  end
  surface.request_to_generate_chunks(position, 1)
  surface.force_generate_chunk_requests()
  local spot = surface.find_non_colliding_position("gun-turret", position, 8, 1)
  assert(spot, "there was no clear spot for the test defence")
  local entity = surface.create_entity({ name = "gun-turret", position = spot, force = game.forces.player })
  assert(entity, "the test defence could not be created")
  entity.destructible = false
  test_defences[#test_defences + 1] = entity
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
