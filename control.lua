-- nexus-bosses: nine summonable bosses on Nexus (see scripts/nb_summon.lua for the life of a summon).
--
-- Events: building, mining and death of the beacons (filtered by name), one on_nth_tick(60) that returns at once
-- when no summon is active, the death events of the active summon (registered while it lasts, see nb_summon.lua),
-- the setting changes and surface creation for the planet fixes. All state is in `storage`.
--
-- Event filters can only be used when an event is registered on its own (LuaBootstrap::on_event: "Can only be used
-- when registering for individual events"): a list of events with filters makes the game refuse to load the mod. The
-- events that share a handler are registered one by one.

local cfg = require("lib.nb_data")
local state = require("scripts.nb_state")
local nexus = require("scripts.nb_nexus")
local progress = require("scripts.nb_progress")
local summon = require("scripts.nb_summon")
require("scripts.nb_interface")

-- Filters of the events of the beacons: their names only.
local beacon_filters = {}
for _, id in ipairs(cfg.ORDER) do
  beacon_filters[#beacon_filters + 1] = { filter = "name", name = cfg.beacon_name(id) }
end

---A beacon appeared: placed by a player, built by a robot, created by a script, revived from a ghost or cloned.
---@param event EventData.on_built_entity|EventData.on_robot_built_entity|EventData.script_raised_built|EventData.script_raised_revive
local function on_built(event)
  local entity = event.entity
  if not (entity and entity.valid) then
    return
  end
  local player = nil
  if event.player_index then
    player = game.get_player(event.player_index)
  end
  summon.on_built(entity, player)
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

---A beacon was picked up by a player or a robot.
---@param event EventData.on_player_mined_entity|EventData.on_robot_mined_entity
local function on_mined(event)
  summon.on_beacon_mined(event.entity)
end

for _, event_id in ipairs({ defines.events.on_player_mined_entity, defines.events.on_robot_mined_entity }) do
  script.on_event(event_id, on_mined, beacon_filters)
end

script.on_event(defines.events.on_segmented_unit_died, summon.on_segmented_unit_died,
  { { filter = "name", name = "nexus-host-worm" } })

script.on_event(defines.events.on_surface_created, function(event)
  nexus.on_surface_created(event.surface_index)
end)

script.on_event(defines.events.on_runtime_mod_setting_changed, function()
  nexus.on_settings_changed()
end)

-- the first circle is researched by the script when the shield stabilizer is not there to do it
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

-- An administrator's way out of any stuck trial.
commands.add_command("nexus-bosses-abort", { "nexus-bosses.command-abort-help" }, function(command)
  local player = command.player_index and game.get_player(command.player_index) or nil
  if player and not player.admin then
    player.print({ "nexus-bosses.msg-admin-only" })
    return
  end
  local aborted = summon.abort(false)
  local message = aborted and { "nexus-bosses.msg-abort-done" } or { "nexus-bosses.msg-abort-nothing" }
  if player then
    player.print(message)
  else
    game.print(message)
  end
end)
