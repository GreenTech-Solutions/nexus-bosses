-- Remote interface "nexus-bosses".
-- The public API for other mods is api_version(), get_state().defeated and open_codex(); its contract and the promise of
-- compatibility are in README.md, "Remote API". Do not change them without a major version and a new API_VERSION; new
-- fields and new optional arguments may come in any version. Everything else here is for tests and debugging and may
-- change in any version.
--   api_version()                      the version of the public API: API_VERSION
--   get_state()                        plain mod state, including the active summon, victories and guard warnings
--   set_ignore_player_presence(bool)   the countdown runs without a player on Nexus (a headless test has none)
--   set_countdown(seconds?)            the countdown of the next summons in seconds, nil restores the setting
--   abort_summon(destroy_bosses?)      ends the active summon without a victory; true also destroys its entities
--   get_pending_data()                 pending telegraph data for tests and debugging
--   set_tracked_health(unit_number, health) changes a tracked entity's health for tests and debugging
--   set_next_colossus(variant_id) selects the next Colossus variant for tests and debugging
--   find_log(force_name, boss_id)      finds the expedition log of a boss, as opening its wreck would
--   toggle_detector(player_index)      as the shortcut of the signal detector
--   open_codex(player_index, boss_id?) opens the codex of the signal on the page of a boss
--   find_lair(force_name, boss_id)     finds the lair of a boss, as two crossing bearings would; returns its position
--   set_finder(unit_number, boss_id?)  points a direction finder at a boss
--   wake_ruin(position)                wakes the attractor ruin nearest to a position, storm or not
--   find_story(force_name, key)        finds the log of the camp ("camp") or of the last stand ("last_stand")
--   defeat(force_name, boss_id)         records a test victory and syncs unlocks and the vault
--   close_reliquary(player_index)       calls the reliquary close handler for a test player
--   repair_pylon(force_name, boss_id, quality)  repairs the pylon of a lair, as a trophy of that quality would
--   resist(entity_name)                reads an entity's combat resistances for tests and debugging
--   hallucinate(player_index, kind?)   a hallucination now: 1 shade, 2 whisper, 3 false alarm, 4 vignette and whisper

local cfg = require("lib.nb_data")
local state = require("scripts.nb_state")
local resistance = require("scripts.nb_resist")
local summon = require("scripts.nb_summon")
local expedition = require("scripts.nb_expedition")
local codex = require("scripts.nb_codex")
local bearing = require("scripts.nb_bearing")
local storms = require("scripts.nb_storms")
local progress = require("scripts.nb_progress")
local story = require("scripts.nb_story")
local vault = require("scripts.nb_vault")
local whisper = require("scripts.nb_whisper")

-- The version of the public API. It grows only when the public part breaks, together with a major version of the mod.
local API_VERSION = 1

remote.add_interface("nexus-bosses", {
  api_version = function()
    return API_VERSION
  end,
  get_state = state.snapshot,
  set_ignore_player_presence = function(value)
    assert(type(value) == "boolean", "nexus-bosses.set_ignore_player_presence: expected a boolean")
    storage.ignore_presence = value
  end,
  set_countdown = function(seconds)
    assert(seconds == nil or (type(seconds) == "number" and seconds >= 1 and seconds % 1 == 0),
      "nexus-bosses.set_countdown: expected a positive integer or nil")
    storage.countdown_override = seconds
  end,
  abort_summon = function(destroy_bosses)
    return summon.abort(destroy_bosses == true)
  end,
  get_pending_data = summon.pending_data,
  set_tracked_health = function(unit_number, health)
    assert(type(unit_number) == "number" and unit_number > 0 and unit_number % 1 == 0,
      "nexus-bosses.set_tracked_health: expected a positive unit number")
    assert(type(health) == "number" and health > 0,
      "nexus-bosses.set_tracked_health: expected positive health")
    return summon.set_tracked_health(unit_number, health)
  end,
  set_next_colossus = function(variant_id)
    assert(type(variant_id) == "string", "nexus-bosses.set_next_colossus: expected a variant id")
    summon.set_next_colossus(variant_id)
  end,
  find_log = function(force_name, boss_id)
    expedition.find_log(force_name, boss_id)
  end,
  resist = function(entity_name)
    assert(type(entity_name) == "string", "nexus-bosses.resist: expected an entity name")
    local weak, strong = resistance.of(entity_name)
    return { weak = weak, strong = strong }
  end,
  toggle_detector = function(player_index)
    expedition.toggle_detector(assert(game.get_player(player_index), "nexus-bosses.toggle_detector: no such player"))
  end,
  open_codex = function(player_index, boss_id)
    local player = assert(game.get_player(player_index), "nexus-bosses.open_codex: no such player")
    -- checked before the window is built: an unknown id would leave it half filled
    assert(boss_id == nil or boss_id == "expedition" or cfg.BOSSES[boss_id], "nexus-bosses.open_codex: no such boss")
    codex.open(player, boss_id)
  end,
  find_lair = function(force_name, boss_id)
    return bearing.find_lair(force_name, boss_id)
  end,
  set_finder = function(unit_number, boss_id)
    ---@type {entity: LuaEntity}|nil
    local finder = storage.bearing.finders[unit_number]
    if not (finder and finder.entity.valid) then
      error("nexus-bosses.set_finder: no direction finder")
    end
    bearing.choose(finder.entity, boss_id)
  end,
  wake_ruin = function(position)
    return storms.wake_nearest(position)
  end,
  find_story = function(force_name, key)
    story.find(force_name, key)
    if key == "camp" then
      vault.earn(game.forces[force_name], "camp")
    end
  end,
  defeat = function(force_name, boss_id)
    assert(type(force_name) == "string", "nexus-bosses.defeat: expected a force name")
    assert(type(boss_id) == "string" and cfg.BOSSES[boss_id], "nexus-bosses.defeat: expected a boss id")
    local force = game.forces[force_name]
    if not force then
      error("nexus-bosses.defeat: no such force")
    end
    progress.mark_defeated(force, boss_id)
    progress.sync_unlocks(force, false)
    vault.sync(force)
  end,
  close_reliquary = function(player_index)
    local player = assert(game.get_player(player_index), "nexus-bosses.close_reliquary: no such player")
    vault.on_reliquary_closed(player)
  end,
  repair_pylon = function(force_name, boss_id, quality)
    local force = game.forces[force_name]
    if not (force and cfg.BOSSES[boss_id] and cfg.PYLON_WEAKEN[quality]) then
      error("nexus-bosses.repair_pylon: bad force, boss or quality")
    end
    bearing.repair_pylon(force, boss_id, quality)
  end,
  hallucinate = function(player_index, kind)
    local player = game.get_player(player_index)
    if not player then
      error("nexus-bosses.hallucinate: no such player")
    end
    whisper.force(player, kind)
  end,
})
