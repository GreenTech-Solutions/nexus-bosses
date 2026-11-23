-- Tests for migrations from older saves.

local cfg = require("lib.nb_data")
local helpers = require("tests.helpers")
local migrate = require("scripts.nb_migrate")
local progress = require("scripts.nb_progress")
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
    for _, name in ipairs({ "bm-summon", "vault-relic", "lair-guards", "glyphs", "whisper-timers", "camp-parts" }) do
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
      and storage.migrated["lair-guards"] == true and storage.migrated.glyphs == true
      and storage.migrated["whisper-timers"] == true and storage.migrated["camp-parts"] == true) then
      error("the migration did not mark every migration as complete")
    end
  end)

  test("every migration of run is listed in NAMES", function()
    local expected = {}
    local old_migrated = copy(storage.migrated) or {}
    local old_vault = copy(storage.vault)
    local old_relic = old_vault and old_vault.relic
    local old_done = copy(storage.guards.done) or {}
    local old_whisper_next = copy(storage.whisper.next) or {}

    storage.migrated = {}
    for _, name in ipairs(migrate.NAMES) do
      expected[name] = true
      remote.call("nexus-bosses", "forget_migration", name)
    end

    remote.call("nexus-bosses", "migrate")
    local actual = {}
    for name, done in pairs(storage.migrated) do
      if done == true then
        actual[name] = true
      end
    end
    assert(same(expected, actual), "M.NAMES does not match the migrations run marks done")

    local new_relic = storage.vault and storage.vault.relic
    if new_relic and new_relic ~= old_relic and new_relic.valid then
      new_relic.destroy()
    end
    storage.vault = old_vault
    storage.guards.done = old_done
    storage.whisper.next = old_whisper_next
    storage.migrated = old_migrated
  end)

  test("a new game keeps the guards of a found lair", function()
    local force = game.forces.player
    local surface = helpers.nexus()
    local boss_id = cfg.ORDER[3]
    local spot = surface.find_non_colliding_position(cfg.PYLON, { x = 300, y = 300 }, 10, 1)
    assert(spot, "there was no clear spot for the new game test pylon")
    local pylon = surface.create_entity({ name = cfg.PYLON, position = spot, force = "neutral" })
    assert(pylon, "the new game test pylon could not be created")

    local old_found = copy(storage.bearing.found) or {}
    local old_wins = copy(storage.bearing.wins) or {}
    local old_pylons = copy(storage.bearing.pylons) or {}
    local old_done = copy(storage.guards.done) or {}
    local old_migrated = copy(storage.migrated) or {}
    storage.bearing.found = { [force.name] = { [boss_id] = game.tick } }
    storage.bearing.wins = { [force.name] = {} }
    storage.bearing.pylons = { [boss_id] = pylon }
    storage.guards.done = {}
    storage.migrated = {}
    migrate.mark_done()

    remote.call("nexus-bosses", "migrate")
    assert(not storage.guards.done["lair:" .. boss_id], "a new game's found lair was marked as already guarded")

    storage.bearing.found = old_found
    storage.bearing.wins = old_wins
    storage.bearing.pylons = old_pylons
    storage.guards.done = old_done
    storage.migrated = old_migrated
    if pylon.valid then
      pylon.destroy()
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

  test("a camp made before the stage parts trades its advanced photon processors for the part of the Whisper", function()
    local previous_camp = storage.story.places.camp
    local surface = helpers.nexus()
    local spot = surface.find_non_colliding_position(cfg.CAMP, { x = 400, y = -400 }, 20, 1)
    assert(spot, "there was no clear spot for the camp migration test")
    local camp = surface.create_entity({ name = cfg.CAMP, position = spot, force = "neutral" })
    assert(camp, "the camp migration test container could not be created")
    storage.story.places.camp = { entity = camp, position = camp.position }

    local inventory = assert(camp.get_inventory(defines.inventory.chest), "the test camp has no chest inventory")
    assert(inventory.insert({ name = "advanced-photon-processor", count = 3 }) == 3,
      "the old camp processors could not be inserted")
    remote.call("nexus-bosses", "forget_migration", "camp-parts")
    remote.call("nexus-bosses", "migrate")

    assert(inventory.get_item_count("advanced-photon-processor") == 0,
      "the camp migration left advanced photon processors in the ship")
    assert(inventory.get_item_count(cfg.CIRCLES[1].part) == 3,
      "the camp migration did not replace the processors with three parts of the Whisper")

    storage.story.places.camp = previous_camp
    if camp.valid then
      camp.destroy()
    end
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

  test("the vault relic migration places one relic after Silence was researched", function()
    local force = game.forces.player
    local technology = force.technologies[cfg.SILENCE_TECH]
    local surface = game.get_surface(cfg.VAULT_SURFACE) or game.create_surface(cfg.VAULT_SURFACE)
    for _, relic in ipairs(surface.find_entities_filtered({ name = cfg.RELIC })) do
      relic.destroy()
    end
    storage.vault.relic = nil
    if technology then
      progress.research(force, cfg.SILENCE_TECH)
    end
    local old_marker = storage.migrated["vault-relic"]
    storage.migrated["vault-relic"] = nil

    remote.call("nexus-bosses", "migrate")
    local relics = surface.find_entities_filtered({ name = cfg.RELIC })
    assert(#relics == 1, "the vault relic migration did not place exactly one relic")
    if not (storage.vault.relic and storage.vault.relic.valid) then
      error("the migrated relic was not stored")
    end
    remote.call("nexus-bosses", "migrate")
    assert(surface.count_entities_filtered({ name = cfg.RELIC }) == 1,
      "repeating the vault relic migration created a second relic")

    relics[1].destroy()
    storage.vault.relic = nil
    storage.migrated["vault-relic"] = old_marker
  end)

  test("the lair guard migration skips old found lairs and ones with wins or pylons", function()
    local force = game.forces.player
    local surface = helpers.nexus()
    local win_boss = cfg.ORDER[1]
    local pylon_boss = cfg.ORDER[2]
    local untouched_boss = cfg.ORDER[3]
    local spot = surface.find_non_colliding_position(cfg.PYLON, { x = 300, y = 300 }, 10, 1)
    assert(spot, "there was no clear spot for the migration test pylon")
    local pylon = surface.create_entity({ name = cfg.PYLON, position = spot, force = "neutral" })
    assert(pylon, "the migration test pylon could not be created")

    local old_found = copy(storage.bearing.found) or {}
    local old_wins = copy(storage.bearing.wins) or {}
    local old_pylons = copy(storage.bearing.pylons) or {}
    local old_done = copy(storage.guards.done) or {}
    local old_migrated = copy(storage.migrated) or {}
    storage.bearing.found = { [force.name] = {
      [win_boss] = game.tick,
      [pylon_boss] = game.tick,
      [untouched_boss] = game.tick,
    } }
    storage.bearing.wins = { [force.name] = { [win_boss] = 1 } }
    storage.bearing.pylons = { [pylon_boss] = pylon }
    storage.guards.done = {}
    storage.migrated = {
      ["bm-summon"] = true,
      ["vault-relic"] = true,
      glyphs = true,
      ["whisper-timers"] = true,
    }

    remote.call("nexus-bosses", "migrate")
    assert(storage.guards.done["lair:" .. win_boss] == true, "a lair with a recorded win was not marked done")
    assert(storage.guards.done["lair:" .. pylon_boss] == true, "a lair with a pylon was not marked done")
    assert(not storage.guards.done["lair:" .. untouched_boss], "a found lair without a win or pylon was marked done")

    storage.bearing.found = old_found
    storage.bearing.wins = old_wins
    storage.bearing.pylons = old_pylons
    storage.guards.done = old_done
    storage.migrated = old_migrated
    if pylon.valid then
      pylon.destroy()
    end
  end)
end)
