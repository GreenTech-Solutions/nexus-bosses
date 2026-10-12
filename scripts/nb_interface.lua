-- Remote interface "nexus-bosses", for tests and debugging.
--   get_state()                        the active summon and the victories per force
--   set_ignore_player_presence(bool)   the countdown runs without a player on Nexus (a headless test has none);
--                                      the bosses of Big Monsters still need one
--   abort_summon(destroy_bosses?)      ends the active summon without a victory; true also destroys its entities
--   find_log(force_name, boss_id)      finds the expedition log of a boss, as opening its wreck would
--   toggle_detector(player_index)      as the shortcut of the signal detector
--   open_codex(player_index, boss_id?) opens the codex of the signal on the page of a boss

local state = require("scripts.nb_state")
local summon = require("scripts.nb_summon")
local expedition = require("scripts.nb_expedition")
local codex = require("scripts.nb_codex")

remote.add_interface("nexus-bosses", {
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
})
