-- Tests for the player's hallucinations.

local helpers = require("tests.helpers")
local util = require("scripts.nb_util")

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
end)
