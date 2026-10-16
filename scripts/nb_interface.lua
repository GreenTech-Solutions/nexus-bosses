-- Remote interface "nexus-bosses".
-- The public API for other mods is api_version(), get_state().defeated and open_codex(); its contract and the promise of
-- compatibility are in README.md, "Remote API". Do not change them without a major version and a new API_VERSION; new
-- fields and new optional arguments may come in any version. Everything else here is for tests and debugging and may
-- change in any version.
--   api_version()                      the version of the public API: API_VERSION
--   get_state()                        the active summon and the victories per force
--   set_ignore_player_presence(bool)   the countdown runs without a player on Nexus (a headless test has none);
--                                      the bosses of Big Monsters still need one
--   abort_summon(destroy_bosses?)      ends the active summon without a victory; true also destroys its entities
--   find_log(force_name, boss_id)      finds the expedition log of a boss, as opening its wreck would
--   toggle_detector(player_index)      as the shortcut of the signal detector
--   open_codex(player_index, boss_id?) opens the codex of the signal on the page of a boss
--   find_lair(force_name, boss_id)     finds the lair of a boss, as two crossing bearings would; returns its position
--   set_finder(unit_number, boss_id?)  points a direction finder at a boss
--   wake_ruin(position)                wakes the attractor ruin nearest to a position, storm or not
--   find_story(force_name, key)        finds the log of the camp ("camp") or of the last stand ("last_stand")
--   repair_pylon(force_name, boss_id, quality)  repairs the pylon of a lair, as a trophy of that quality would
--   hallucinate(player_index, kind?)   a hallucination now: 1 shade, 2 whisper, 3 false alarm, 4 vignette and whisper

local cfg = require("lib.nb_data")
local state = require("scripts.nb_state")
local summon = require("scripts.nb_summon")
local expedition = require("scripts.nb_expedition")
local codex = require("scripts.nb_codex")
local bearing = require("scripts.nb_bearing")
local storms = require("scripts.nb_storms")
local story = require("scripts.nb_story")
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
  abort_summon = function(destroy_bosses)
    return summon.abort(destroy_bosses == true)
  end,
  find_log = function(force_name, boss_id)
    expedition.find_log(force_name, boss_id)
  end,
  toggle_detector = function(player_index)
    expedition.toggle_detector(assert(game.get_player(player_index), "nexus-bosses.toggle_detector: no such player"))
  end,
  open_codex = function(player_index, boss_id)
    codex.open(assert(game.get_player(player_index), "nexus-bosses.open_codex: no such player"), boss_id)
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
  end,
  repair_pylon = function(force_name, boss_id, quality)
    local force = game.forces[force_name]
    if not (force and cfg.BOSSES[boss_id] and cfg.PYLON_SHARES[quality]) then
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
