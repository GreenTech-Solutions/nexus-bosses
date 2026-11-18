-- Tests for pylon weakening and the harder lair fights.

local cfg = require("lib.nb_data")
local helpers = require("tests.helpers")
local util = require("scripts.nb_util")

describe("pylon and lair mechanics", function()
  before_each(function()
    helpers.reset()
    helpers.nexus()
  end)

  test("mechanic intervals account for pylon weakening and lair frequency", function()
    local base = { weaken = 0, frequency = 1 }
    assert(util.interval(base, 12) == 12, "an unmodified interval should stay unchanged")
    assert(util.interval({ weaken = 0.5, frequency = 1 }, 12, true) == 24,
      "a half-strength pylon should double a weakened mechanic's interval")
    assert(util.interval({ weaken = 0.5, frequency = 1 }, 12) == 12,
      "a pylon should not change a mechanic that is weakened by frequency")
    assert(util.interval({ weaken = 1, frequency = 1 }, 12, true) == nil,
      "a legendary pylon should disable a weakened mechanic")
    assert(util.interval({ weaken = 1, frequency = 1 }, 12) == 12,
      "a legendary pylon should not disable an unaffected interval")
    local lair_interval = util.interval({ weaken = 0, frequency = 4 / 3 }, 12)
    assert(lair_interval and math.abs(lair_interval - 9) < 0.0001,
      "a lair should make the mechanic more frequent")
  end)

  test("mechanic due timers start once, repeat, and clear on a nil interval", function()
    local state = {}
    assert(not util.due(state, "mark", 0, 12), "the first timer call should only set its next use")
    assert(state.mark == 12, "the timer did not store its next use")
    assert(not util.due(state, "mark", 11, 12), "the timer fired before its interval")
    assert(util.due(state, "mark", 12, 12), "the timer did not fire at its next use")
    assert(state.mark == 24, "the repeating timer did not move to its next use")
    assert(not util.due(state, "mark", 13, nil), "a nil interval should never fire")
    assert(state.mark == nil, "a nil interval should clear its stored use")
    assert(not util.due(state, "mark", 24, nil), "a nil interval should remain disabled")
  end)

  test("a legendary pylon leaves the Queen at full health and prevents her nests", function()
    helpers.nexus()
    local lair = remote.call("nexus-bosses", "find_lair", "player", "arachnid-queen") --[[@as MapPosition.struct|nil]]
    assert(lair, "the Queen lair was not found")
    remote.call("nexus-bosses", "repair_pylon", "player", "arachnid-queen", "legendary")
    helpers.light("arachnid-queen", lair)

    local damaged_at
    helpers.on_active(1200, function(summon, ticks_since_active)
      if not damaged_at then
        assert(summon.lair and summon.weaken == 1, "the Queen summon did not receive its legendary pylon")
        local queen = helpers.tracked(summon, "boss", cfg.QUEEN)
        assert(queen and queen.health and queen.initial, "the Queen is missing from the summon snapshot")
        assert(math.abs(queen.health - queen.initial) <= 1, "the Queen's health changed when she appeared")
        assert(remote.call("nexus-bosses", "set_tracked_health", queen.unit_number, queen.initial * 0.6),
          "the Queen health could not be lowered below two thirds")
        damaged_at = game.tick
      elseif damaged_at and game.tick >= damaged_at + 5 * 60 then
        assert(helpers.role_count(summon, "nest") == 0 and not helpers.pending(summon, "nests"),
          "the legendary pylon did not disable the Queen's nests")
        helpers.reset()
        return true
      end
      if ticks_since_active >= 1200 then
        error("the Queen lair test timed out: " .. helpers.describe_summon(summon))
      end
    end)
  end)

  test("a rare pylon sets the Storm Guardian weakening in the summon snapshot", function()
    local lair = remote.call("nexus-bosses", "find_lair", "player", "storm-guardian") --[[@as MapPosition.struct|nil]]
    assert(lair, "the Storm Guardian lair was not found")
    remote.call("nexus-bosses", "repair_pylon", "player", "storm-guardian", "rare")
    helpers.light("storm-guardian", lair)

    helpers.on_active(1200, function(summon)
      assert(summon.lair and math.abs(summon.weaken - 0.5) < 0.0001,
        "the rare pylon did not weaken the Storm Guardian by 50 %")
      helpers.reset()
      return true
    end)
  end)

  test("a rare pylon leaves three soldiers in the Commander's lair drop", function()
    local lair = remote.call("nexus-bosses", "find_lair", "player", "last-commander") --[[@as MapPosition.struct|nil]]
    assert(lair, "the Last Commander lair was not found")
    remote.call("nexus-bosses", "repair_pylon", "player", "last-commander", "rare")
    helpers.light("last-commander", lair)

    helpers.on_active(6000, function(summon, ticks_since_active)
      assert(summon.lair and math.abs(summon.weaken - 0.5) < 0.0001,
        "the rare pylon did not weaken the Commander by 50 %")
      if helpers.pending(summon, "drop") then
        local pending_data = remote.call("nexus-bosses", "get_pending_data")
        ---@cast pending_data {kind: string, at: integer, data: table}[]
        for _, entry in ipairs(pending_data) do
          if entry.kind == "drop" then
            assert(entry.data.count == 3, "the rare pylon did not reduce the Commander drop to three soldiers")
            return true
          end
        end
        error("the Commander drop has no debug data")
      end
      if ticks_since_active >= 6000 then
        error("the Commander did not queue its lair drop in time: " .. helpers.describe_summon(summon))
      end
    end)
  end)
end)
