-- Tests for migrations from older saves.

local cfg = require("lib.nb_data")
local helpers = require("tests.helpers")
local records = require("scripts.nb_records")

---@param value any
---@return any
local function copy(value)
  if type(value) ~= "table" then
    return value
  end
  local result = {}
  for key, entry in pairs(value) do
    result[key] = copy(entry)
  end
  return result
end

---@param left any
---@param right any
---@return boolean
local function same(left, right)
  if type(left) ~= type(right) then
    return false
  end
  if type(left) ~= "table" then
    return left == right
  end
  for key, value in pairs(left) do
    if not same(value, right[key]) then
      return false
    end
  end
  for key in pairs(right) do
    if left[key] == nil then
      return false
    end
  end
  return true
end

---@param surface LuaSurface
---@param position MapPosition
---@param name string
---@param quality string
---@return integer
local function item_count(surface, position, name, quality)
  local count = 0
  for _, entity in ipairs(surface.find_entities_filtered({ position = position, radius = 8, name = "item-on-ground" })) do
    local stack = entity.stack
    if entity.valid and stack.valid_for_read and stack.name == name and stack.quality.name == quality then
      count = count + stack.count
    end
  end
  return count
end

describe("save migrations", function()
  before_each(function()
    helpers.reset()
    helpers.nexus()
  end)

  test("migration is idempotent", function()
    for _, name in ipairs({ "bm-summon", "vault-relic", "glyphs", "whisper-timers" }) do
      remote.call("nexus-bosses", "forget_migration", name)
    end
    storage.whisper.next[1] = game.tick + 600

    remote.call("nexus-bosses", "migrate")
    local first_state = remote.call("nexus-bosses", "get_state")
    local first_migrations = copy(storage.migrated)
    local first_whisper_timers = copy(storage.whisper.next)

    remote.call("nexus-bosses", "migrate")
    local second_state = remote.call("nexus-bosses", "get_state")
    assert(same(first_state, second_state), "the second migration call changed the mod state")
    assert(same(first_migrations, storage.migrated), "the second migration call changed migration markers")
    assert(same(first_whisper_timers, storage.whisper.next), "the second migration call changed whisper timers")
    if not (storage.migrated["bm-summon"] == true and storage.migrated["vault-relic"] == true
      and storage.migrated.glyphs == true and storage.migrated["whisper-timers"] == true) then
      error("the migration did not mark every migration as complete")
    end
  end)

  test("a found camp earns its migration glyph", function()
    local force = game.forces.player
    local force_name = force.name
    local previous_found = copy(storage.story.found[force_name])
    local previous_logs = storage.expedition.logs[force_name]
    local previous_wins = storage.bearing.wins[force_name]
    local previous_earned = storage.vault.earned[force_name]
    local previous_revealed = storage.vault.revealed[force_name]

    storage.expedition.logs[force_name] = {}
    for _, boss_id in ipairs(cfg.ORDER) do
      storage.expedition.logs[force_name][boss_id] = game.tick
    end
    storage.bearing.wins[force_name] = { [cfg.ORDER[1]] = 1 }
    remote.call("nexus-bosses", "find_story", force_name, "camp")
    storage.vault.earned[force_name] = nil
    storage.vault.revealed[force_name] = nil
    remote.call("nexus-bosses", "forget_migration", "glyphs")

    remote.call("nexus-bosses", "migrate")
    local state = remote.call("nexus-bosses", "get_state") --[[@as {vault: {earned: table<string, table<string, boolean>|nil>}}]]
    local earned = state.vault.earned[force_name]
    assert(earned and earned.camp == true, "finding the camp did not earn the migration glyph")
    assert(earned.logs == true, "finding all nine logs did not earn the migration glyph")
    assert(earned.lair == true, "winning in a lair did not earn the migration glyph")

    storage.story.found[force_name] = previous_found
    storage.expedition.logs[force_name] = previous_logs
    storage.bearing.wins[force_name] = previous_wins
    storage.vault.earned[force_name] = previous_earned
    storage.vault.revealed[force_name] = previous_revealed
  end)

  test("a legacy BM summon is cancelled and its beacon is returned", function()
    local surface = helpers.nexus()
    local beacon = helpers.light("arachnid-queen", { x = 0, y = 0 }, "rare")
    local summon = storage.summon --[[@as NbSummon|nil]]
    if not summon then
      error("the test summon was not stored")
    end
    summon.phase = "active"
    local legacy_summon = summon --[[@as table]]
    legacy_summon.bm = { attempts = 1 }
    local item = summon.item
    local quality = summon.quality
    local position = summon.position
    local before = item_count(surface, position, item, quality)
    local unit_position = surface.find_non_colliding_position("behemoth-biter", { x = 4, y = 0 }, 8, 1)
    local unit = unit_position and surface.create_entity({ name = "behemoth-biter", position = unit_position, force = "enemy" })
    assert(unit, "the test's tracked entity could not be created")
    records.add(summon, unit, true, "boss")
    remote.call("nexus-bosses", "forget_migration", "bm-summon")

    remote.call("nexus-bosses", "migrate")
    local remaining_summon = storage.summon
    if remaining_summon ~= nil then
      error("the legacy BM summon was not cleared")
    end
    assert(not beacon.valid, "the legacy summon beacon was not removed")
    assert(not unit.valid, "the legacy summon entity was not destroyed")
    assert(item_count(surface, position, item, quality) == before + 1, "the legacy summon beacon was not returned with its quality")
  end)

  test("a legacy own boss fight continues after migration", function()
    helpers.light("arachnid-queen", { x = 0, y = 0 })
    ---@type NbSummon|nil
    local stored
    ---@type LuaEntity|nil
    local entity
    ---@type integer|nil
    local active_seconds
    helpers.on_active(10 * 60, function(summon)
      if not stored then
        helpers.defend()

        stored = storage.summon --[[@as NbSummon|nil]]
        assert(stored, "the active test summon was not stored")
        local boss = helpers.tracked(summon, "boss", cfg.QUEEN)
        assert(boss, "the active test summon has no tracked Queen")
        entity = helpers.find_entity(helpers.nexus(), boss.name, boss.position)
        assert(entity, "the active test Queen entity is missing")

        stored.phase_index = nil
        stored.undefended = nil
        stored.weaken = nil
        stored.frequency = nil
        stored.pending = nil
        stored.health_bar = nil
        remote.call("nexus-bosses", "migrate")
        active_seconds = stored.active_seconds
        return
      end

      if not stored or not entity or not entity.valid or active_seconds == nil then
        error("the legacy own boss migration setup was incomplete")
      end
      if summon.active_seconds < active_seconds + 2 then
        return
      end

      assert(stored.phase == "active", "the legacy own boss fight did not remain active after migration")
      local health_before = entity.health
      assert(health_before ~= nil, "the active test Queen has no health")
      entity.damage(10000, "player", "physical")
      local health_after = entity.health
      assert(health_after and health_after < health_before - 1, "the active test Queen did not take damage")

      local state = remote.call("nexus-bosses", "get_state")
      local migrated = state and state.summon
      assert(migrated and migrated.phase == "active", "the legacy own boss fight ended after taking damage")
      assert(type(migrated.phase_index) == "number", "the migrated fight snapshot has no numeric phase_index")
      remote.call("nexus-bosses", "abort_summon", true)
      return true
    end)
  end)
end)
