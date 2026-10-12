-- nexus-bosses: nine summonable bosses on Nexus (scripts/nb_summon.lua follows one summon from beacon to victory).
--
-- Event filters work only when an event is registered on its own (LuaBootstrap::on_event: "Can only be used when
-- registering for individual events"), so the events that share a handler are registered one by one. The death event
-- is registered by the summon, with the names of its bosses, while it lasts.

local cfg = require("lib.nb_data")
local state = require("scripts.nb_state")
local nexus = require("scripts.nb_nexus")
local progress = require("scripts.nb_progress")
local summon = require("scripts.nb_summon")
require("scripts.nb_interface")

local beacon_filters = {}
for _, id in ipairs(cfg.ORDER) do
  beacon_filters[#beacon_filters + 1] = { filter = "name", name = cfg.beacon_name(id) }
end

---@param event EventData.on_built_entity|EventData.on_robot_built_entity|EventData.script_raised_built|EventData.script_raised_revive
local function on_built(event)
  summon.on_built(event.entity, event.player_index and game.get_player(event.player_index) or nil)
end

for _, event_id in ipairs({
  defines.events.on_built_entity,
  defines.events.on_robot_built_entity,
  defines.events.script_raised_built,
  defines.events.script_raised_revive,
}) do
  script.on_event(event_id, on_built, beacon_filters)
end

script.on_event(defines.events.on_entity_cloned, function(event)
  summon.on_built(event.destination, nil)
end, beacon_filters)

---@param event EventData.on_player_mined_entity|EventData.on_robot_mined_entity
local function on_mined(event)
  summon.on_beacon_mined(event.entity)
end

for _, event_id in ipairs({ defines.events.on_player_mined_entity, defines.events.on_robot_mined_entity }) do
  script.on_event(event_id, on_mined, beacon_filters)
end

script.on_event(defines.events.on_segmented_unit_died, summon.on_segmented_unit_died,
  { { filter = "name", name = cfg.DEVOURER } })

script.on_event(defines.events.on_surface_created, function(event)
  nexus.on_surface_created(event.surface_index)
end)

script.on_event(defines.events.on_runtime_mod_setting_changed, nexus.on_settings_changed)

script.on_event(defines.events.on_research_finished, function(event)
  progress.on_research_finished(event.research)
end)

script.on_event(defines.events.on_forces_merged, function(event)
  progress.on_forces_merged(event.source_name, event.destination)
end)

script.on_nth_tick(60, function(event)
  summon.step()
  nexus.on_second(event.tick)
end)

script.on_init(function()
  state.init()
  nexus.on_init()
  progress.on_configuration_changed() -- a game that has discovered Nexus already
end)

script.on_configuration_changed(function()
  state.init()
  nexus.on_configuration_changed()
  progress.on_configuration_changed()
  summon.on_configuration_changed()
end)

script.on_load(function()
  summon.restore_events()
end)

commands.add_command("nexus-bosses-abort", { "nexus-bosses.command-abort-help" }, function(command)
  local player = command.player_index and game.get_player(command.player_index) or nil
  if player and not player.admin then
    player.print({ "nexus-bosses.msg-admin-only" })
    return
  end
  local message = summon.abort(false) and { "nexus-bosses.msg-abort-done" } or { "nexus-bosses.msg-abort-nothing" }
  if player then
    player.print(message)
  else
    game.print(message)
  end
end)
