-- Tests for the no-defence defeat condition.

local cfg = require("lib.nb_data")
local helpers = require("tests.helpers")
local spawn = require("scripts.nb_spawn")
local util = require("scripts.nb_util")

local QUEEN = "arachnid-queen"

---@param state table
---@param force_name string
---@return table<string, boolean>
local function copy_defeated(state, force_name)
  local result = {}
  for boss_id, defeated in pairs(state.defeated[force_name] or {}) do
    result[boss_id] = defeated
  end
  return result
end

---@param before table<string, boolean>
---@param after table<string, boolean>
local function assert_defeated_unchanged(before, after)
  for boss_id in pairs(cfg.BOSSES) do
    assert((before[boss_id] == true) == (after[boss_id] == true),
      "the no-defence defeat changed victory state for " .. boss_id)
  end
end

describe("no-defence defeat", function()
  before_each(function()
    helpers.reset()
    helpers.nexus()
  end)

  test("an unsupported Queen leaves after 60 seconds and the beacon is lost", function()
    local surface = helpers.nexus()
    local force = game.forces.player
    local position = { x = 0, y = 0 }
    local summon = { force = force.name }
    local targets = spawn.targets(surface, summon, position, cfg.DEFENCE_RADIUS,
      { military = true, claimed = false })
    for _, target in ipairs(targets) do
      if target.valid then
        target.destroy()
      end
    end
    helpers.move_players_away(position, cfg.DEFENCE_RADIUS)
    assert(#spawn.targets(surface, summon, position, cfg.DEFENCE_RADIUS,
      { military = true, claimed = false }) == 0, "the unsupported Queen test still has military targets")
    local before = remote.call("nexus-bosses", "get_state") --[[@as table]]
    local defeated_before = copy_defeated(before, force.name)
    helpers.light(QUEEN, position)

    local started_at
    local elapsed = 0
    async(75 * 60)
    on_tick(function()
      elapsed = elapsed + 1
      local active = helpers.active()
      if active and active.phase == "active" then
        started_at = started_at or game.tick
      elseif started_at then
        local fight_ticks = game.tick - started_at
        assert(fight_ticks >= 59 * 60, "the unsupported Queen left before the 60-second window")
        assert(fight_ticks <= 75 * 60, "the unsupported Queen did not leave within the test window")
        local state = remote.call("nexus-bosses", "get_state") --[[@as table]]
        assert(state and state.summon == nil, "the unsupported Queen summon remained active")
        assert(surface.count_entities_filtered({
          name = cfg.BEACON_PREFIX .. QUEEN,
          position = position,
          radius = 5,
        }) == 0, "the unsupported Queen beacon was returned")
        local returned_beacons = 0
        for _, item in ipairs(surface.find_entities_filtered({
          name = "item-on-ground",
          position = position,
          radius = 8,
        })) do
          local stack = item.stack
          if item.valid and stack.valid_for_read and stack.name == cfg.BEACON_PREFIX .. QUEEN then
            returned_beacons = returned_beacons + stack.count
          end
        end
        assert(returned_beacons == 0, "the unsupported Queen beacon item was refunded")
        assert_defeated_unchanged(defeated_before, copy_defeated(state, force.name))
        helpers.restore_players()
        done()
        return false
      end
      if elapsed >= 75 * 60 then
        helpers.restore_players()
        error("the unsupported Queen summon did not end within 75 seconds")
      end
    end)
  end)

  test("a Queen with an unclaimed turret nearby remains defended", function()
    local position = { x = 0, y = 0 }
    local force = game.forces.player
    local target_filter = { force = force.name }
    local targets = spawn.targets(helpers.nexus(), target_filter, position, cfg.DEFENCE_RADIUS,
      { military = true, claimed = false })
    for _, target in ipairs(targets) do
      if target.valid then
        target.destroy()
      end
    end
    helpers.move_players_away(position, cfg.DEFENCE_RADIUS)
    helpers.light(QUEEN, position)
    local turret = helpers.defend({ x = 20, y = 0 })
    assert(turret.valid and not turret.destructible, "the nearby test turret must be indestructible")
    assert(util.distance(turret.position, position) <= 30, "the nearby test turret must be within 30 tiles of the beacon")

    helpers.on_active(75 * 60, function(summon)
      assert(summon.undefended == nil, string.format(
        "the nearby turret did not keep the fight defended: active_seconds=%s undefended=%s",
        tostring(summon.active_seconds), tostring(summon.undefended)))
      if summon.active_seconds >= 70 then
        remote.call("nexus-bosses", "abort_summon", true)
        helpers.restore_players()
        return true
      end
    end)
  end)
end)
