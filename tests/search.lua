-- Tests for the detector and guards of expedition finds.

local cfg = require("lib.nb_data")
local expedition = require("scripts.nb_expedition")
local helpers = require("tests.helpers")
local progress = require("scripts.nb_progress")
local util = require("scripts.nb_util")

local QUEEN = "arachnid-queen"
local GUARD_DELAY = 3 * 60

---@param boss_id string
---@return {entity: LuaEntity, position: MapPosition}|nil
local function wreck_of(boss_id)
  local wreck = storage.expedition.wrecks[boss_id]
  if not (wreck and wreck.entity.valid) then
    expedition.spawn_stage(cfg.BOSSES[boss_id].circle)
    wreck = storage.expedition.wrecks[boss_id]
  end
  return wreck
end

---@param player LuaPlayer
---@param surface LuaSurface
---@param center MapPosition
---@return LuaEntity, LuaEntity|nil, MapPosition|nil, LuaSurface|nil
local function place_test_character(player, surface, center)
  local old_character = player.character
  local old_position = old_character and util.copy_position(old_character.position)
  local old_surface = old_character and old_character.surface
  local wanted = util.offset(center, 0, 30)
  local position = surface.find_non_colliding_position("character", wanted, 4, 0.5) or wanted
  local character = surface.create_entity({ name = "character", position = position, force = player.force })
  assert(character, "could not create a test character beside the Queen wreck")
  player.set_controller({ type = defines.controllers.god })
  player.teleport(position, surface)
  player.set_controller({ type = defines.controllers.character, character = character })
  assert(math.abs(util.distance(character.position, center) - 30) < 4,
    "the test character is not 30 tiles from the Queen wreck")
  return character, old_character, old_position, old_surface
end

---@param player LuaPlayer
---@param character LuaEntity
---@param old_character LuaEntity|nil
---@param old_position MapPosition|nil
---@param old_surface LuaSurface|nil
local function restore_character(player, character, old_character, old_position, old_surface)
  if old_character and old_character.valid then
    if old_position and old_surface then
      player.teleport(old_position, old_surface)
    end
    player.set_controller({ type = defines.controllers.character, character = old_character })
  else
    player.set_controller({ type = defines.controllers.god })
  end
  if character.valid then
    character.destroy()
  end
end

---@param state table
---@param boss_id string
---@return table|nil
local function pending_for(state, boss_id)
  for _, pending in ipairs(state.guards.pending) do
    if pending.boss_id == boss_id then
      return pending
    end
  end
end

---@param surface LuaSurface
---@param boss_id string
---@param center MapPosition
---@param radius number
---@return integer
local function precursor_count(surface, boss_id, center, radius)
  local names = {}
  for _, name in ipairs(cfg.BOSSES[boss_id].precursors) do
    names[name] = true
  end
  local count = 0
  for _, entity in ipairs(surface.find_entities_filtered({ position = center, radius = radius, force = "enemy", type = "unit" })) do
    if names[entity.name] then
      count = count + 1
    end
  end
  return count
end

---@param force_name string
---@param boss_id string
---@return table<string, integer>, integer|nil
local function clear_log(force_name, boss_id)
  local logs = storage.expedition.logs[force_name]
  if not logs then
    logs = {}
    storage.expedition.logs[force_name] = logs
  end
  local previous = logs[boss_id]
  logs[boss_id] = nil
  return logs, previous
end

---@param logs table<string, integer>
---@param boss_id string
---@param previous integer|nil
local function restore_log(logs, boss_id, previous)
  logs[boss_id] = previous
end

describe("expedition search", function()
  before_each(function()
    helpers.reset()
    helpers.nexus()
  end)

  test("the Queen's guards emerge after a three-second warning and only once", function()
    local surface = helpers.nexus()
    local wreck = wreck_of(QUEEN)
    assert(wreck and wreck.entity.valid, "the Queen wreck is missing")
    local player = assert(game.get_player(1), "the first test player is missing")
    local force_name = player.force.name --[[@as string]]
    local logs, previous_log = clear_log(force_name, QUEEN)
    local character, old_character, old_position, old_surface = place_test_character(player, surface, wreck.position)

    local elapsed = 0
    local warning_at
    local initial_count
    local recheck_at
    async(600)
    on_tick(function()
      elapsed = elapsed + 1
      local state = remote.call("nexus-bosses", "get_state")
      ---@cast state {guards: {done: table<string, integer|nil>, pending: {at: integer, boss_id: string}[]}}
      local pending = pending_for(state, QUEEN)

      if warning_at and not initial_count and game.tick < warning_at then
        assert(precursor_count(surface, QUEEN, wreck.position, 48) == 0,
          "Queen precursors appeared before the warning expired")
      end

      if not warning_at and pending then
        warning_at = pending.at
        assert(warning_at >= game.tick + GUARD_DELAY - 60,
          "the guards were not queued for a three-second warning")
        assert(precursor_count(surface, QUEEN, wreck.position, 48) == 0,
          "Queen precursors appeared before the warning expired")
        player.teleport({ x = 10000, y = 10000 }, surface)
      elseif warning_at and not initial_count and game.tick >= warning_at + 60 then
        initial_count = precursor_count(surface, QUEEN, wreck.position, 48)
        assert(initial_count > 0, "Queen precursors did not emerge four seconds after approach")
        assert(not pending, "the pending guard wave remained after emerging")
        assert(state.guards.done["wreck:" .. QUEEN], "the Queen wreck was not marked done")
        player.teleport(util.offset(wreck.position, 0, 30), surface)
        recheck_at = game.tick + 60
      elseif recheck_at and game.tick >= recheck_at then
        assert(not pending, "a second approach queued another guard wave")
        assert(state.guards.done["wreck:" .. QUEEN], "the Queen wreck lost its once-only marker")
        assert(precursor_count(surface, QUEEN, wreck.position, 48) <= initial_count,
          "a second approach created more Queen precursors")
        restore_character(player, character, old_character, old_position, old_surface)
        restore_log(logs, QUEEN, previous_log)
        done()
        return false
      end

      if elapsed >= 600 then
        error("the Queen guard test timed out waiting for the warning and emergence")
      end
    end)
  end)

  test("a wreck with a found log does not wake its guards", function()
    local surface = helpers.nexus()
    local wreck = wreck_of(QUEEN)
    assert(wreck and wreck.entity.valid, "the Queen wreck is missing")
    local player = assert(game.get_player(1), "the first test player is missing")
    local force_name = player.force.name --[[@as string]]
    local logs, previous_log = clear_log(force_name, QUEEN)
    expedition.find_log(force_name, QUEEN)
    local character, old_character, old_position, old_surface = place_test_character(player, surface, wreck.position)

    local elapsed = 0
    async(120)
    on_tick(function()
      elapsed = elapsed + 1
      local state = remote.call("nexus-bosses", "get_state")
      ---@cast state {guards: {pending: {boss_id: string}[]}}
      assert(not pending_for(state, QUEEN), "a logged wreck queued guards")
      assert(precursor_count(surface, QUEEN, wreck.position, 48) == 0,
        "a logged wreck spawned Queen precursors")
      if elapsed >= 120 then
        restore_character(player, character, old_character, old_position, old_surface)
        restore_log(logs, QUEEN, previous_log)
        done()
        return false
      end
    end)
  end)

  test("a victory reveals the nearest undefeated boss's wreck first", function()
    helpers.nexus()
    for stage = 1, #cfg.CIRCLES do
      expedition.spawn_stage(stage)
    end
    local queen = wreck_of(QUEEN)
    local watcher = wreck_of("watcher")
    assert(queen and queen.entity.valid and watcher and watcher.entity.valid,
      "the Queen or Watcher wreck is missing")

    local force_name = "nexus-bosses-search-test"
    local force = game.forces[force_name] or game.create_force(force_name)
    storage.progress[force_name] = { defeated = {} }
    storage.expedition.logs[force_name] = {}
    storage.expedition.marked[force_name] = {}
    progress.mark_defeated(force, QUEEN)
    for _, boss_id in ipairs(cfg.ORDER) do
      if boss_id ~= QUEEN and boss_id ~= "watcher" then
        expedition.find_log(force_name, boss_id)
      end
    end

    assert(util.distance(queen.position, watcher.position) > 0,
      "the Queen and Watcher wrecks unexpectedly share a position")
    expedition.reveal_next(force, queen.position)
    local state = remote.call("nexus-bosses", "get_state")
    ---@cast state {expedition: {marked: table<string, table<string, boolean>>}}
    assert(state.expedition.marked[force_name].watcher,
      "the victory did not mark the Watcher wreck after the Queen was defeated")

    storage.progress[force_name] = nil
    storage.expedition.logs[force_name] = nil
    storage.expedition.marked[force_name] = nil
  end)
end)
