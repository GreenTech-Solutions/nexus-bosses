-- Tests for resistance data and the fight bar's log-gated resistance label.

local helpers = require("tests.helpers")
local util = require("scripts.nb_util")

local DAMAGE_TYPES = { "physical", "impact", "fire", "acid", "poison", "explosion", "laser", "electric" }
local DAMAGE_TYPE_SET = {}
for _, name in ipairs(DAMAGE_TYPES) do
  DAMAGE_TYPE_SET[name] = true
end

---@param value any
---@param key string
---@return boolean
local function contains_localised_key(value, key)
  if type(value) ~= "table" then
    return false
  end
  if value[1] == key then
    return true
  end
  for _, part in pairs(value) do
    if contains_localised_key(part, key) then
      return true
    end
  end
  return false
end

---@param value any
---@return boolean
local function contains_number(value)
  if type(value) == "number" then
    return true
  end
  if type(value) == "table" then
    for _, part in pairs(value) do
      if contains_number(part) then
        return true
      end
    end
  end
  return false
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

  test("every fight track is a valid ambient sound", function()
    local game_helpers = _G.helpers
    assert(#util.FIGHT_TRACKS == 5, "there should be five fight tracks")
    for _, track in ipairs(util.FIGHT_TRACKS) do
      assert(game_helpers.is_valid_ambient_sound(track.name), "invalid ambient sound: " .. track.name)
    end
  end)

  test("weak resistance is the lowest non-uniform share, and equal zero shares are not weak", function()
    local candidate_name = "stone-wall"
    local prototype = prototypes.entity[candidate_name]
    local shares = {}
    local candidate_weak = {}
    local minimum = math.huge
    local first
    local all_equal = true
    local has_negative = false
    for _, damage_type in ipairs(DAMAGE_TYPES) do
      local entry = prototype.resistances and prototype.resistances[damage_type]
      local share = entry and entry.percent or 0
      shares[damage_type] = share
      minimum = math.min(minimum, share)
      if first == nil then
        first = share
      elseif share ~= first then
        all_equal = false
      end
      if share < 0 then
        has_negative = true
      end
    end
    assert(not has_negative, candidate_name .. " must not have negative resistance shares")
    assert(not all_equal and minimum < 0.3,
      candidate_name .. " must have non-uniform resistance shares with a minimum below 0.3")
    for _, damage_type in ipairs(DAMAGE_TYPES) do
      if shares[damage_type] == minimum then
        candidate_weak[#candidate_weak + 1] = damage_type
      end
    end

    local result = remote.call("nexus-bosses", "resist", candidate_name)
    assert(result, "the resistance debug data is missing for " .. candidate_name)
    assert(#result.weak == #candidate_weak, "the weakest damage types were not selected")
    for _, damage_type in ipairs(candidate_weak) do
      assert(contains(result.weak, damage_type), "the weakest damage type is missing: " .. damage_type)
    end

    local zero_name = "wooden-chest"
    local zero = prototypes.entity[zero_name]
    for _, damage_type in ipairs(DAMAGE_TYPES) do
      local entry = zero.resistances and zero.resistances[damage_type]
      assert(entry == nil, zero_name .. " must have no resistance entry for " .. damage_type)
    end
    local all_zero = remote.call("nexus-bosses", "resist", zero_name)
    assert(all_zero and #all_zero.weak == 0, "an entity with equal zero shares should have no weak types")
  end)

  local status_bosses = {
    "arachnid-queen", "watcher", "rogue-spidertron", "twin-maws", "colossus", "plague-hulk",
    "storm-guardian", "devourer", "last-commander",
  }
  for _, id in ipairs(status_bosses) do
    local boss_id = id
    test("the " .. boss_id .. " bar names its next event", function()
      helpers.light(boss_id, { 0, 0 })
      helpers.on_active(30 * 60, function(summon, ticks_since_active)
        local status = summon.health_bar and summon.health_bar.status
        if status then
          if boss_id == "storm-guardian" then
            -- Its unchanged status is the current storm state and contains no time or health threshold.
            assert(type(status) == "table", "the Storm Guardian status should describe its current storm state")
          else
            assert(contains_number(status), "the status does not contain a time or health threshold")
          end
          remote.call("nexus-bosses", "abort_summon", true)
          return true
        end
        if ticks_since_active >= 30 * 60 then
          error("the " .. boss_id .. " status did not appear in the first 30 seconds")
        end
      end)
    end)
  end

  test("the fight bar reports the Storm Guardian's electric immunity through the main entity", function()
    remote.call("nexus-bosses", "find_log", "player", "storm-guardian")
    helpers.light("storm-guardian", { 0, 0 })
    helpers.on_active(600, function(summon, ticks_since_active)
      local resist = summon.health_bar and summon.health_bar.resist
      if resist then
        assert(contains_localised_key(resist[3], "damage-type-name.electric"),
          "the Storm Guardian fight bar should show electric resistance")
        remote.call("nexus-bosses", "abort_summon", true)
        return true
      end
      if ticks_since_active >= 600 then
        error("the Storm Guardian resistance caption did not appear in the fight bar")
      end
    end)
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

  test("the Twin Maws bar shows resistance for both copies through the main entity path", function()
    remote.call("nexus-bosses", "find_log", "player", "twin-maws")
    helpers.light("twin-maws", { 0, 0 })
    helpers.on_active(600, function(summon, ticks_since_active)
      if summon.health_bar and summon.health_bar.resist then
        local resist = summon.health_bar.resist
        assert(contains_localised_key(resist, "entity-name.nexus-maw-fire"),
          "the Twin Maws bar is missing the fire maw resistance")
        assert(contains_localised_key(resist, "entity-name.nexus-maw-acid"),
          "the Twin Maws bar is missing the acid maw resistance")
        remote.call("nexus-bosses", "abort_summon", true)
        return true
      end
      if ticks_since_active >= 600 then
        error("the Twin Maws resistance caption did not include both copies")
      end
    end)
  end)
end)
