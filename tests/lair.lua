-- Tests for pylon weakening and the harder lair fights.

local cfg = require("lib.nb_data")
local helpers = require("tests.helpers")

---@param summon table
---@param role string
---@param name string|nil
---@return table|nil
local function tracked(summon, role, name)
  for _, record in ipairs(summon.tracked or {}) do
    if record.role == role and (not name or record.name == name) then
      return record
    end
  end
end

---@param summon table
---@param role string
---@return boolean
local function has_record(summon, role)
  for _, record in ipairs(summon.tracked or {}) do
    if record.role == role and not record.dead and not record.gone then
      return true
    end
  end
  return false
end

---@param summon table
---@param kind string
---@return boolean
local function has_pending(summon, kind)
  for _, entry in ipairs(summon.pending or {}) do
    if entry.kind == kind then
      return true
    end
  end
  return false
end

describe("pylon and lair mechanics", function()
  before_each(function()
    helpers.reset()
    helpers.nexus()
  end)

  test("mechanic intervals account for pylon weakening and lair frequency", function()
    local interval = function(seconds, weaken, frequency)
      return remote.call("nexus-bosses", "interval", seconds, weaken, frequency)
    end

    assert(interval(12, 0, 1) == 12, "an unmodified interval should stay unchanged")
    assert(interval(12, 0.5, 1) == 24, "a half-strength pylon should double the interval")
    assert(interval(12, 1, 1) == nil, "a legendary pylon should disable the mechanic")
    local lair_interval = interval(12, 0, 4 / 3)
    assert(lair_interval and math.abs(lair_interval - 9) < 0.0001,
      "a lair should make the mechanic more frequent")
  end)

  test("a legendary pylon leaves the Queen at full health and prevents her nests", function()
    helpers.nexus()
    local lair = remote.call("nexus-bosses", "find_lair", "player", "arachnid-queen") --[[@as MapPosition.struct|nil]]
    assert(lair, "the Queen lair was not found")
    remote.call("nexus-bosses", "repair_pylon", "player", "arachnid-queen", "legendary")
    helpers.light("arachnid-queen", lair)

    local damaged_at
    local elapsed = 0
    local last_summon
    async(1200)
    on_tick(function()
      elapsed = elapsed + 1
      local summon = helpers.active()
      last_summon = summon
      if summon and summon.phase == "active" and not damaged_at then
        assert(summon.lair and summon.weaken == 1, "the Queen summon did not receive its legendary pylon")
        local queen = tracked(summon, "boss", cfg.QUEEN)
        assert(queen and queen.health and queen.initial, "the Queen is missing from the summon snapshot")
        assert(math.abs(queen.health - queen.initial) <= 1, "the Queen's health changed when she appeared")
        assert(remote.call("nexus-bosses", "set_tracked_health", queen.unit_number, queen.initial * 0.6),
          "the Queen health could not be lowered below two thirds")
        damaged_at = game.tick
      elseif damaged_at and game.tick >= damaged_at + 5 * 60 then
        local current = helpers.active()
        assert(current and current.phase == "active", "the Queen fight ended before the mechanic check")
        assert(not has_record(current, "nest") and not has_pending(current, "nests"),
          "the legendary pylon did not disable the Queen's nests")
        helpers.reset()
        done()
        return false
      end
      if elapsed >= 1200 then
        error("the Queen lair test timed out: " .. helpers.describe_summon(last_summon))
      end
    end)
  end)

  test("a rare pylon sets the Storm Guardian weakening in the summon snapshot", function()
    local lair = remote.call("nexus-bosses", "find_lair", "player", "storm-guardian") --[[@as MapPosition.struct|nil]]
    assert(lair, "the Storm Guardian lair was not found")
    remote.call("nexus-bosses", "repair_pylon", "player", "storm-guardian", "rare")
    helpers.light("storm-guardian", lair)

    helpers.wait_phase("active", 1200, function(summon)
      assert(summon.lair and math.abs(summon.weaken - 0.5) < 0.0001,
        "the rare pylon did not weaken the Storm Guardian by 50 %")
      helpers.reset()
    end)
  end)
end)
