-- Smoke test for the mod's in-game test harness.

local helpers = require("tests.helpers")

describe("nexus-bosses harness", function()
  before_each(function()
    helpers.reset()
    helpers.nexus()
  end)

  test("a Queen summon reaches the fight and aborts", function()
    local beacon = helpers.light("arachnid-queen", { 0, 0 })
    assert(beacon.valid, "the Queen beacon was not created")
    local summon = helpers.active()
    assert(summon and summon.phase == "countdown", "the Queen summon did not start its countdown")
    helpers.wait_phase("active", 600, function(active)
      assert(active.health_share > 0, "the boss has no health")
      assert(#active.tracked > 0, "the summon has no tracked entities")
      remote.call("nexus-bosses", "abort_summon", true)
      assert(helpers.active() == nil, "the active summon was not cleared")
    end)
  end)
end)
