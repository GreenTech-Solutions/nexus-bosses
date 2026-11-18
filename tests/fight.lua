-- Tests for resistance data and the fight bar's log-gated resistance label.

local helpers = require("tests.helpers")

local DAMAGE_TYPES = { "physical", "impact", "fire", "acid", "poison", "explosion", "laser", "electric" }
local DAMAGE_TYPE_SET = {}
for _, name in ipairs(DAMAGE_TYPES) do
  DAMAGE_TYPE_SET[name] = true
end

---@param list string[]
---@param value string
---@return boolean
local function contains(list, value)
  for _, item in ipairs(list) do
    if item == value then
      return true
    end
  end
  return false
end

describe("fight bar tactics", function()
  before_each(function()
    helpers.reset()
    helpers.nexus()
  end)

  test("reports the Storm Guardian's electric immunity", function()
    local result = remote.call("nexus-bosses", "resist", "nexus-storm-guardian") --[[@as {weak: string[], strong: string[]}|nil]]
    assert(result, "the resistance debug data is missing")
    assert(contains(result.strong, "electric"), "electric should be a strong damage type for the Storm Guardian")
  end)

  test("ignores damage types outside the player weapon list", function()
    ---@type LuaEntityPrototype|nil
    local saucer = prototypes.entity["maf_flying_saucer_8"]
    local resistances = saucer and saucer.resistances
    assert(saucer, "the maf_flying_saucer_8 prototype is missing")
    ---@type string|nil
    local outside_type
    for damage_type in pairs(resistances or {}) do
      if not DAMAGE_TYPE_SET[damage_type] then
        outside_type = damage_type
        break
      end
    end
    assert(outside_type, "maf_flying_saucer_8 must have a resistance type outside DAMAGE_TYPES")

    local result = remote.call("nexus-bosses", "resist", "maf_flying_saucer_8") --[[@as {weak: string[], strong: string[]}|nil]]
    assert(result, "the resistance debug data is missing")
    for _, damage_types in ipairs({ result.weak, result.strong }) do
      for _, damage_type in ipairs(damage_types) do
        assert(DAMAGE_TYPE_SET[damage_type], "unexpected damage type in resistance data: " .. damage_type)
      end
    end
    assert(not contains(result.weak, "rubia-kinetic") and not contains(result.strong, "rubia-kinetic"),
      "rubia-kinetic should not be shown")
  end)

  test("shows resistance in the headless bar snapshot only after the force finds the log", function()
    helpers.light("arachnid-queen", { 0, 0 })
    local found_log = false
    local elapsed = 0
    async(600)
    on_tick(function()
      elapsed = elapsed + 1
      local summon = helpers.active()
      if summon and summon.phase == "active" then
        if not found_log then
          assert(summon.health_bar and summon.health_bar.resist == nil,
            "resistance should stay hidden until the force finds the log")
          remote.call("nexus-bosses", "find_log", "player", "arachnid-queen")
          found_log = true
        elseif summon.health_bar and summon.health_bar.resist then
          assert(summon.health_bar.resist[1] == "nexus-bosses.bar-resist",
            "the headless snapshot should contain the resistance caption shown by the bar")
          done()
          return false
        end
      end
      if elapsed >= 600 then
        error("the resistance caption did not appear in the bar snapshot after the log was found")
      end
    end)
  end)
end)
