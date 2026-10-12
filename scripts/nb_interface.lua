-- Remote interface "nexus-bosses", for tests and debugging.
--   get_state()                        the active summon and the victories per force
--   set_ignore_player_presence(bool)   the countdown runs without a player on Nexus (a headless test has none);
--                                      the bosses of Big Monsters still need one
--   abort_summon(destroy_bosses?)      ends the active summon without a victory; true also destroys its entities

local state = require("scripts.nb_state")
local summon = require("scripts.nb_summon")

remote.add_interface("nexus-bosses", {
  get_state = state.snapshot,
  set_ignore_player_presence = function(value)
    assert(type(value) == "boolean", "nexus-bosses.set_ignore_player_presence: expected a boolean")
    storage.ignore_presence = value
  end,
  abort_summon = function(destroy_bosses)
    return summon.abort(destroy_bosses == true)
  end,
})
