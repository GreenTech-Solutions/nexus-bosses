-- Remote interface "nexus-bosses" for tests and debugging.
--   get_state()                        the active summon, the victories per force, the state of the circles
--   set_ignore_player_presence(bool)   debug/test switch: the countdown of a summon runs even when no player of the
--                                      force stands on Nexus (a headless run has no players). Default false.
--   abort_summon(destroy_bosses?)      ends the active summon without a victory; true also destroys its entities

local state = require("scripts.nb_state")
local summon = require("scripts.nb_summon")

remote.add_interface("nexus-bosses", {
  get_state = function()
    return state.snapshot()
  end,

  set_ignore_player_presence = function(value)
    if type(value) ~= "boolean" then
      error("nexus-bosses.set_ignore_player_presence: expected a boolean, got " .. type(value))
    end
    storage.ignore_presence = value
  end,

  abort_summon = function(destroy_bosses)
    return summon.abort(destroy_bosses == true)
  end,
})
