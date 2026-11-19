-- Tests for Convergence access, glyph earns and the reliquary.

local cfg = require("lib.nb_data")
local expedition = require("scripts.nb_expedition")
local helpers = require("tests.helpers")
local util = require("scripts.nb_util")
local vault = require("scripts.nb_vault")

---@param values table
---@return integer
local function count_entries(values)
  local count = 0
  for _ in pairs(values) do
    count = count + 1
  end
  return count
end

describe("vault finale", function()
  before_each(function()
    helpers.reset()
    helpers.nexus()
  end)

  test("the vault follows Convergence and its reliquary consumes one warp key", function()
    local player = assert(game.get_player(1), "the first test player is missing")
    local force = player.force --[[@as LuaForce]]
    storage.progress[force.name] = { defeated = {} }
    local silence = force.technologies[cfg.SILENCE_TECH]
    if silence then
      silence.researched = false
    end
    remote.call("nexus-bosses", "find_story", force.name, "camp")
    vault.earn(force, "lair")

    local state = remote.call("nexus-bosses", "get_state")
    assert(state and state.vault.position == nil,
      "the vault was marked before the Convergence was defeated")

    for circle_index = 1, #cfg.CIRCLES - 1 do
      for _, boss_id in ipairs(cfg.CIRCLES[circle_index].bosses) do
        remote.call("nexus-bosses", "defeat", force.name, boss_id)
      end
    end
    local convergence = cfg.CIRCLES[#cfg.CIRCLES]
    for index = 1, #convergence.bosses - 1 do
      remote.call("nexus-bosses", "defeat", force.name, convergence.bosses[index])
    end
    state = remote.call("nexus-bosses", "get_state")
    assert(state and state.vault.position == nil,
      "the vault was marked before all three Convergence bosses were defeated")
    remote.call("nexus-bosses", "defeat", force.name, convergence.bosses[#convergence.bosses])
    state = remote.call("nexus-bosses", "get_state")
    assert(state and state.vault.position ~= nil,
      "the vault was not marked after all three Convergence bosses were defeated")
    assert(storage.vault.earned[force.name].camp, "finding the camp did not earn its glyph")
    assert(storage.vault.earned[force.name].lair, "the pre-vault lair glyph was not kept")
    assert(storage.vault.revealed[force.name][1], "the pre-vault lair glyph was not revealed with the lock")
    assert(count_entries(storage.vault.revealed[force.name]) == count_entries(storage.vault.earned[force.name]),
      "the vault did not reveal one glyph per earned source")

    local inventory = assert(player.get_main_inventory(), "the test player has no main inventory")
    inventory.insert({ name = cfg.BADGE, count = 1 })
    vault.on_console_opened(player)
    assert(inventory.get_item_count(cfg.BADGE) == 0, "the commander's badge was not consumed")
    assert(storage.vault.earned[force.name].badge, "the badge did not earn a glyph")
    assert(storage.vault.revealed[force.name][2], "the badge glyph was not revealed")

    if not player.character then
      local surface = helpers.nexus()
      local position = surface.find_non_colliding_position("character", { x = 0, y = 0 }, 10, 0.5) or { x = 0, y = 0 }
      local character = surface.create_entity({ name = "character", position = position, force = force })
      assert(character, "could not create a character to enter the vault")
      player.set_controller({ type = defines.controllers.character, character = character })
    end
    storage.vault.open = true -- The test focuses on the reliquary after the lock has opened.
    vault.descend(player)
    local reliquary = assert(storage.vault.reliquary, "the vault reliquary was not built")
    local reliquary_inventory = reliquary.get_inventory(defines.inventory.chest)
    assert(reliquary_inventory, "the reliquary has no inventory")

    if silence then
      assert(reliquary_inventory.get_item_count(cfg.WARP_KEY) == 0, "the reliquary was not empty of warp keys")
      assert(not (storage.vault.relic and storage.vault.relic.valid), "the relic was placed before the first warp key")
      remote.call("nexus-bosses", "close_reliquary", player.index)
      assert(not silence.researched, "Silence was researched without a warp key")
      assert(not (storage.vault.relic and storage.vault.relic.valid), "the relic was placed without a warp key")

      reliquary_inventory.insert({ name = cfg.WARP_KEY, quality = "uncommon", count = 1 })
      remote.call("nexus-bosses", "close_reliquary", player.index)
      if not silence.researched then
        error("placing a warp key in the reliquary did not research Silence")
      end
      assert(reliquary_inventory.get_item_count(cfg.WARP_KEY) == 0, "the warp key was not consumed")
      assert(storage.vault.relic and storage.vault.relic.valid, "the relic was not placed after the warp key")
    else
      if not (storage.vault.relic and storage.vault.relic.valid) then
        error("the relic was not placed without the Silence gate")
      end
    end
  end)

  test("the last wreck log earns the log glyph only once", function()
    local player = assert(game.get_player(1), "the first test player is missing")
    local force = player.force --[[@as LuaForce]]
    local last_boss_id = cfg.ORDER[#cfg.ORDER]
    local already_logged_id = cfg.ORDER[1]
    local wreck = storage.expedition.wrecks[last_boss_id]
    if not (wreck and wreck.entity.valid) then
      expedition.spawn_stage(cfg.BOSSES[last_boss_id].circle)
      wreck = storage.expedition.wrecks[last_boss_id]
    end
    assert(wreck and wreck.entity.valid, "could not create the last test wreck")
    local logged_wreck = storage.expedition.wrecks[already_logged_id]
    if not (logged_wreck and logged_wreck.entity.valid) then
      expedition.spawn_stage(cfg.BOSSES[already_logged_id].circle)
      logged_wreck = storage.expedition.wrecks[already_logged_id]
    end
    assert(logged_wreck and logged_wreck.entity.valid, "could not create the previously logged test wreck")

    local old_logs = storage.expedition.logs[force.name]
    local logs = {}
    for _, boss_id in ipairs(cfg.ORDER) do
      if boss_id ~= last_boss_id then
        logs[boss_id] = game.tick
      end
    end
    storage.expedition.logs[force.name] = logs
    local ok, err = pcall(function()
      local codex = { open = function() end }
      assert(not expedition.on_wreck_opened(player, logged_wreck.entity, codex),
        "opening a previously logged wreck returned true")
      assert(expedition.on_wreck_opened(player, wreck.entity, codex),
        "opening the ninth wreck did not return true")
      assert(not expedition.on_wreck_opened(player, wreck.entity, codex),
        "opening a wreck after all logs were found returned true")
    end)
    storage.expedition.logs[force.name] = old_logs
    if not ok then
      error(err)
    end
  end)

  test("a researched Silence raises one relic when the vault is built", function()
    local player = assert(game.get_player(1), "the first test player is missing")
    local force = player.force --[[@as LuaForce]]
    local technology = force.technologies[cfg.SILENCE_TECH]
    if not technology then
      return
    end

    local nexus = helpers.nexus()
    local old_character = player.character
    local old_position = old_character and util.copy_position(old_character.position)
    local old_surface = old_character and old_character.surface
    if old_character then
      player.teleport({ x = 0, y = 0 }, nexus)
    else
      local position = nexus.find_non_colliding_position("character", { x = 0, y = 0 }, 10, 0.5) or { x = 0, y = 0 }
      local character = nexus.create_entity({ name = "character", position = position, force = force })
      assert(character, "could not create a character to build the vault")
      player.set_controller({ type = defines.controllers.character, character = character })
    end

    local existing_surface = game.get_surface(cfg.VAULT_SURFACE)
    if existing_surface then
      for _, entity in ipairs(existing_surface.find_entities_filtered({})) do
        if entity.valid then
          entity.destroy()
        end
      end
    end
    storage.vault = {}
    vault.init()
    storage.vault.open = true
    technology.researched = true

    local ok, failure = pcall(function()
      vault.descend(player)
      local surface = assert(game.get_surface(cfg.VAULT_SURFACE), "the vault surface was not created")
      local relics = surface.find_entities_filtered({ name = cfg.RELIC })
      assert(#relics == 1, "a researched Silence did not raise exactly one relic when the vault was built")
      if not (storage.vault.relic and storage.vault.relic.valid) then
        error("the built relic was not stored")
      end

      vault.descend(player)
      relics = surface.find_entities_filtered({ name = cfg.RELIC })
      assert(#relics == 1, "building the vault again created a second relic")
    end)

    technology.researched = true
    if old_character and old_position and old_surface and old_character.valid then
      player.teleport(old_position, old_surface)
    end
    if not ok then
      error(failure)
    end
  end)
end)
