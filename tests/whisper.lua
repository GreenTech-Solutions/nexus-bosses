-- Tests for the player's hallucinations.

local helpers = require("tests.helpers")
local util = require("scripts.nb_util")
local cfg = require("lib.nb_data")
local whisper = require("scripts.nb_whisper")

describe("hallucinations", function()
  before_each(function()
    helpers.reset()
    helpers.nexus()
  end)

  test("all four hallucinations can be triggered for a player on Nexus", function()
    local surface = helpers.nexus()
    local player = assert(game.get_player(1), "the first test player is missing")
    local old_character = player.character
    local old_position = old_character and util.copy_position(old_character.position)
    local old_surface = old_character and old_character.surface
    local wanted = { x = 0, y = 0 }
    local position = surface.find_non_colliding_position("character", wanted, 20, 0.5) or wanted
    local character = surface.create_entity({ name = "character", position = position, force = player.force })
    assert(character, "could not create the test character on Nexus")

    player.set_controller({ type = defines.controllers.god })
    player.teleport(position, surface)
    player.set_controller({ type = defines.controllers.character, character = character })

    local ok, failure = pcall(function()
      for kind = 1, 4 do
        remote.call("nexus-bosses", "hallucinate", 1, kind)
      end
    end)

    for unit, shade in pairs(storage.whisper.shades) do
      if shade.entity.valid then
        shade.entity.destroy()
      end
      storage.whisper.shades[unit] = nil
    end
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

    assert(ok, "a hallucination failed: " .. tostring(failure))
  end)

  test("a due hallucination is postponed during a fight on Nexus", function()
    local surface = helpers.nexus()
    local player = assert(game.get_player(1), "the first test player is missing")
    local force = player.force --[[@as LuaForce]]
    local old_character = player.character
    local old_position = old_character and util.copy_position(old_character.position)
    local old_surface = old_character and old_character.surface
    local position = surface.find_non_colliding_position("character", { x = 0, y = 0 }, 20, 0.5) or { x = 0, y = 0 }
    local test_character = old_character
    if old_character then
      player.teleport(position, surface)
    else
      test_character = surface.create_entity({ name = "character", position = position, force = force })
      assert(test_character, "could not create a character for the timer test")
      player.set_controller({ type = defines.controllers.character, character = test_character })
    end

    local old_technologies = {}
    for _, circle in ipairs(cfg.CIRCLES) do
      local technology = force.technologies[circle.tech]
      if technology then
        old_technologies[#old_technologies + 1] = { technology = technology, researched = technology.researched }
        technology.researched = true
      end
    end
    local silence = force.technologies[cfg.SILENCE_TECH]
    if silence then
      old_technologies[#old_technologies + 1] = { technology = silence, researched = silence.researched }
      silence.researched = false
    end

    local old_summon = storage.summon
    local old_due = storage.whisper.next[player.index]
    local old_shades = {}
    for unit in pairs(storage.whisper.shades) do
      old_shades[unit] = true
    end
    storage.summon = { surface_index = surface.index }
    storage.whisper.next[player.index] = game.tick - 1

    local launches = 0
    local ok, failure = pcall(function()
      whisper.on_tick(game.tick, function()
        launches = launches + 1
      end)
    end)

    local deferred_until = storage.whisper.next[player.index]
    local new_shades = 0
    for unit, shade in pairs(storage.whisper.shades) do
      if not old_shades[unit] then
        new_shades = new_shades + 1
        if shade.entity.valid then
          shade.entity.destroy()
        end
        storage.whisper.shades[unit] = nil
      end
    end
    storage.summon = old_summon
    storage.whisper.next[player.index] = old_due
    for _, entry in ipairs(old_technologies) do
      entry.technology.researched = entry.researched
    end
    if old_character and old_position and old_surface and old_character.valid then
      player.teleport(old_position, old_surface)
      player.set_controller({ type = defines.controllers.character, character = old_character })
    elseif test_character and test_character.valid then
      player.set_controller({ type = defines.controllers.god })
      test_character.destroy()
    end

    assert(ok, "the hallucination timer failed: " .. tostring(failure))
    assert(deferred_until and deferred_until > game.tick, "the timer was not moved past the active fight")
    assert(launches == 0, "the hallucination timer launched an event during the fight")
    assert(new_shades == 0, "a hallucination spawned a shade during the fight")
  end)
end)
