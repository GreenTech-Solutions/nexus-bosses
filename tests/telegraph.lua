-- Tests for delayed attacks using the summon snapshot and the test/debug remote functions.

local helpers = require("tests.helpers")

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

---@param element LuaGuiElement
---@param key string
---@param nested_key string
---@return boolean
local function contains_caption(element, key, nested_key)
  if element.type == "label" and contains_localised_key(element.caption, key)
    and contains_localised_key(element.caption, nested_key) then
    return true
  end
  for _, child in pairs(element.children) do
    if contains_caption(child, key, nested_key) then
      return true
    end
  end
  return false
end

---@param a MapPosition
---@param b MapPosition
---@return number
local function distance(a, b)
  ---@cast a MapPosition.struct
  ---@cast b MapPosition.struct
  local dx = a.x - b.x
  local dy = a.y - b.y
  return math.sqrt(dx * dx + dy * dy)
end

describe("boss telegraphs", function()
  before_each(function()
    helpers.reset()
    helpers.nexus()
  end)

  test("the telegraph sound is a sound of the mod", function()
    assert(_G.helpers.is_valid_sound_path("nexus-bosses-telegraph"),
      "the telegraph sound prototype is missing")
  end)

  test("the Codex shows the next Colossus variant before its beacon is built", function()
    local player = game.players[1]
    remote.call("nexus-bosses", "set_next_colossus", "armored")
    remote.call("nexus-bosses", "open_codex", player.index, "colossus")
    local expected = "entity-name.nexus-colossus-armored"
    local frame = player.gui.screen["nexus_bosses_codex"]
    assert(frame and contains_caption(frame, "nexus-bosses.codex-colossus-next", expected),
      "the Colossus page did not show its stored next variant")
    frame.destroy()
  end)

  test("the Queen marks nest positions before the nests appear", function()
    helpers.light("arachnid-queen", { 0, 0 })
    local health_tick
    local nests_at
    helpers.on_active(800, function(summon, ticks_since_active)
      if not health_tick then
        local boss = helpers.tracked(summon, "boss")
        if boss then
          assert(remote.call("nexus-bosses", "set_tracked_health", boss.unit_number, boss.initial * 0.6),
            "the Queen health could not be changed")
          health_tick = game.tick
        end
      elseif not nests_at then
        local entry = helpers.pending(summon, "nests")
        if entry then
          nests_at = entry.at
          assert(nests_at > game.tick, "the nest telegraph did not have a delay")
          assert(helpers.role_count(summon, "nest") == 0, "nests appeared before their telegraph expired")
        elseif game.tick > health_tick + 70 then
          error("the Queen did not queue the nest attack after crossing two thirds health")
        end
      elseif game.tick < nests_at then
        assert(helpers.role_count(summon, "nest") == 0, "nests appeared before their telegraph expired")
      elseif helpers.role_count(summon, "nest") > 0 then
        return true
      elseif game.tick > nests_at + 60 then
        error("the Queen nests did not appear when their telegraph expired")
      end
      if ticks_since_active >= 800 then
        error("the Queen nest telegraph test timed out: " .. helpers.describe_summon(summon))
      end
    end)
  end)

  test("the Devourer rises near the point marked before its dive", function()
    helpers.light("devourer", { 0, 0 })
    local health_tick
    local rise_at
    ---@type MapPosition|nil
    local target
    helpers.on_active(1000, function(summon, ticks_since_active)
      if not health_tick then
        local boss = helpers.tracked(summon, "boss")
        if boss then
          assert(remote.call("nexus-bosses", "set_tracked_health", boss.unit_number, boss.initial * 0.4),
            "the Devourer health could not be changed")
          health_tick = game.tick
        end
      elseif not rise_at then
        local entry = helpers.pending(summon, "rise")
        if entry then
          rise_at = entry.at
          assert(rise_at > game.tick, "the rise telegraph did not have a delay")
          local pending_data = remote.call("nexus-bosses", "get_pending_data")
          ---@cast pending_data {kind: string, at: integer, data: {position: MapPosition}}[]
          for _, detail in ipairs(pending_data) do
            if detail.kind == "rise" and detail.at == rise_at then
              target = detail.data.position
              break
            end
          end
          if not target then
            error("the saved rise position is missing")
          end
        elseif game.tick > health_tick + 70 then
          error("the Devourer did not queue its rise after crossing half health")
        end
      elseif game.tick >= rise_at then
        local boss = helpers.tracked(summon, "boss")
        if target and boss and not boss.hidden and boss.position and boss.health > 0 then
          assert(distance(boss.position, target) < 15, "the Devourer rose more than 15 tiles from the marked point")
          return true
        elseif game.tick > rise_at + 60 then
          error("the Devourer did not rise after its telegraph expired")
        end
      end
      if ticks_since_active >= 1000 then
        error("the Devourer rise test timed out: " .. helpers.describe_summon(summon))
      end
    end)
  end)
end)
