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
local expedition = require("scripts.nb_expedition")
local codex = require("scripts.nb_codex")
local bearing = require("scripts.nb_bearing")
local storms = require("scripts.nb_storms")
local story = require("scripts.nb_story")
local whisper = require("scripts.nb_whisper")
require("scripts.nb_interface")

local beacon_filters = {}
for _, name in ipairs(cfg.beacon_names()) do
  beacon_filters[#beacon_filters + 1] = { filter = "name", name = name }
end
local built_filters = { { filter = "name", name = cfg.FINDER } }
for _, filter in ipairs(beacon_filters) do
  built_filters[#built_filters + 1] = filter
end

---@param entity LuaEntity
---@param player LuaPlayer|nil
local function built(entity, player)
  if entity.name == cfg.FINDER then
    bearing.on_built(entity)
  else
    summon.on_built(entity, player)
  end
end

---@param event EventData.on_built_entity|EventData.on_robot_built_entity|EventData.script_raised_built|EventData.script_raised_revive
local function on_built(event)
  built(event.entity, event.player_index and game.get_player(event.player_index) or nil)
end

for _, event_id in ipairs({
  defines.events.on_built_entity,
  defines.events.on_robot_built_entity,
  defines.events.script_raised_built,
  defines.events.script_raised_revive,
}) do
  script.on_event(event_id, on_built, built_filters)
end

script.on_event(defines.events.on_entity_cloned, function(event)
  built(event.destination, nil)
end, built_filters)

script.on_event(defines.events.on_sector_scanned, function(event)
  bearing.on_sector_scanned(event.radar)
end, { { filter = "name", name = cfg.FINDER } })

script.on_event(defines.events.on_object_destroyed, function(event)
  if event.type == defines.target_type.entity then
    bearing.on_destroyed(event.useful_id)
  end
end)

script.on_event(defines.events.on_chunk_generated, storms.on_chunk_generated)
script.on_event(defines.events.on_gui_selection_state_changed, bearing.on_selection_changed)

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
  local surface = game.get_surface(event.surface_index)
  if surface and surface.name == cfg.PLANET then
    expedition.spawn_open_stages()
    story.sync_all()
  end
end)

script.on_event(defines.events.on_gui_opened, function(event)
  local entity = event.entity
  if not entity then
    return
  end
  local player = game.get_player(event.player_index) --[[@as LuaPlayer]]
  if entity.name:sub(1, #cfg.WRECK_PREFIX) == cfg.WRECK_PREFIX then
    expedition.on_wreck_opened(player, entity, codex)
  elseif entity.name == cfg.FINDER then
    bearing.open_panel(player, entity)
  elseif story.key_of(entity) then
    story.on_opened(player, entity)
  end
end)

script.on_event(defines.events.on_lua_shortcut, function(event)
  local player = game.get_player(event.player_index) --[[@as LuaPlayer]]
  if event.prototype_name == cfg.SHORTCUT_DETECTOR then
    expedition.toggle_detector(player)
  elseif event.prototype_name == cfg.SHORTCUT_CODEX then
    codex.toggle(player)
  end
end)

script.on_event(defines.events.on_gui_click, codex.on_gui_click)
script.on_event(defines.events.on_gui_closed, function(event)
  local entity = event.entity
  if entity and entity.valid and entity.name == cfg.PYLON then
    bearing.on_pylon_closed(game.get_player(event.player_index) --[[@as LuaPlayer]], entity)
  else
    codex.on_gui_closed(event)
  end
end)

script.on_event(defines.events.on_runtime_mod_setting_changed, nexus.on_settings_changed)

script.on_event(defines.events.on_research_finished, function(event)
  progress.on_research_finished(event.research)
  expedition.on_research_finished(event.research)
  story.sync(event.research.force)
end)

script.on_event(defines.events.on_forces_merged, function(event)
  progress.on_forces_merged(event.source_name, event.destination)
end)

script.on_nth_tick(60, function(event)
  summon.step()
  nexus.on_second(event.tick)
  storms.on_second(event.tick)
end)

script.on_nth_tick(30, function(event)
  expedition.detector_tick(event.tick)
  whisper.clear_shades(event.tick)
end)

script.on_nth_tick(whisper.CHECK_TICKS, function(event)
  whisper.on_tick(event.tick)
end)

script.on_init(function()
  state.init()
  expedition.init()
  bearing.init()
  storms.init()
  story.init()
  whisper.init()
  nexus.on_init()
  progress.on_configuration_changed() -- a game that has discovered Nexus already
  expedition.spawn_open_stages()
  story.sync_all()
end)

script.on_configuration_changed(function()
  state.init()
  expedition.init()
  bearing.init()
  storms.init()
  story.init()
  whisper.init()
  expedition.sync_bearing()
  story.sync_all()
  expedition.spawn_open_stages()
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
