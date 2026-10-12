-- The life of a summon.
--
-- "countdown"  the beacon stands, marked by a label, a map tag and alerts. Each second with a player of the force on
--              Nexus the countdown runs down (map setting, 60 s by default); without one it waits. At two thirds and
--              one third of it a precursor wave comes for the beacon from the side the boss will come from. Losing or
--              picking up the beacon cancels the summon.
-- "spawning"   the countdown is over and the beacon is locked. The mod's own bosses appear at once. For a boss of
--              Big Monsters the event is called every two seconds while a player is on Nexus, for up to 60 seconds,
--              until a new boss entity shows up (see nb_bm.lua); none, and the beacon comes back.
-- "active"     the beacon is gone and the fight is on. The victory comes when every required entity has died.
-- Whatever ends a summon, storage.summon becomes nil, so a new beacon can be lit.

local cfg = require("lib.nb_data")
local util = require("scripts.nb_util")
local records = require("scripts.nb_records")
local bm = require("scripts.nb_bm")
local nexus = require("scripts.nb_nexus")
local spawn = require("scripts.nb_spawn")
local progress = require("scripts.nb_progress")
local gui = require("scripts.nb_gui")
local expedition = require("scripts.nb_expedition")
local bearing = require("scripts.nb_bearing")
local story = require("scripts.nb_story")

local M = {}

local BM_WINDOW_SECONDS = 60
local BM_RETRY_TICKS = 120

-- the bosses of the mod: spawn, tick, status, on_victory, release; the names whose death events matter
local OWN = {
  ["arachnid-queen"] = { module = require("scripts.bosses.arachnid-queen"), watch = { cfg.QUEEN } },
  ["twin-maws"] = { module = require("scripts.bosses.twin-maws"), watch = { cfg.MAW_FIRE, cfg.MAW_ACID } },
  ["plague-hulk"] = { module = require("scripts.bosses.plague-hulk"), watch = { cfg.HULK } },
  ["storm-guardian"] = { module = require("scripts.bosses.storm-guardian"), watch = { cfg.GUARDIAN } },
  ["devourer"] = { module = require("scripts.bosses.devourer"), watch = {} }, -- on_segmented_unit_died
}

---@param id string
---@return LocalisedString
local function boss_name(id)
  return { "nexus-bosses.boss-" .. id }
end

---@param summon table
---@return table? # the module of an own boss
local function module_of(summon)
  local own = OWN[summon.boss]
  return own and own.module
end

---@param summon table
---@return LuaForce|nil
local function force_of(summon)
  return game.forces[summon.force]
end

---Gives a beacon item back to the builder, or drops it where it stood.
---@param surface LuaSurface
---@param position MapPosition
---@param item string
---@param quality string|nil
---@param player LuaPlayer|nil
local function give_back(surface, position, item, quality, player)
  local stack = { name = item, count = 1, quality = quality }
  if player and player.valid and player.insert(stack) >= 1 then
    return
  end
  surface.spill_item_stack({ position = position, stack = stack, enable_looted = true, allow_belts = false })
end

-- Death events -------------------------------------------------------------------------------------------------------

local on_entity_died

---@param summon table
local function register_death_events(summon)
  local filters = {}
  for _, name in ipairs(summon.watch) do
    filters[#filters + 1] = { filter = "name", name = name }
  end
  script.on_event(defines.events.on_entity_died, on_entity_died, filters)
end

local function unregister_death_events()
  script.on_event(defines.events.on_entity_died, nil)
end

-- Visuals and alarms -------------------------------------------------------------------------------------------------

---@param summon table
---@return LocalisedString
local function label_text(summon)
  if summon.phase == "spawning" then
    return { "nexus-bosses.label-spawning" }
  elseif summon.paused then
    return { "nexus-bosses.label-paused" }
  end
  return { "nexus-bosses.label-countdown", summon.countdown }
end

---@param summon table
local function update_visuals(summon)
  summon.label.text = label_text(summon)
  if summon.tag and summon.tag.valid and summon.countdown % 5 == 0 then
    summon.tag.text = string.format("[item=%s] %d", summon.item, summon.countdown)
  end
end

---@param summon table
---@param force LuaForce
---@param surface LuaSurface
local function create_visuals(summon, force, surface)
  local x, y = util.xy(summon.position)
  force.chart(surface, { { x - 24, y - 24 }, { x + 24, y + 24 } })
  summon.tag = force.add_chart_tag(surface, {
    position = summon.position,
    text = string.format("[item=%s] %d", summon.item, summon.countdown),
    icon = { type = "item", name = summon.item },
  })
  -- the antenna colours of the beacons (prototypes/nb_items.lua): blue, amber, red
  local tint = ({ { r = 0.55, g = 0.85, b = 1 }, { r = 1, g = 0.8, b = 0.35 }, { r = 1, g = 0.4, b = 0.35 } })[summon.circle]
  summon.circle_fx = rendering.draw_animation({
    animation = "nexus-bosses-summon-circle",
    target = summon.beacon,
    surface = surface,
    tint = tint,
    render_layer = "lower-object",
  })
  summon.label = rendering.draw_text({
    text = label_text(summon),
    surface = surface,
    target = { entity = summon.beacon, offset = { 0, -2.4 } },
    forces = { force },
    color = util.COLORS.warning,
    scale = 1.3,
    alignment = "center",
    vertical_alignment = "middle",
  })
end

---@param summon table
---@param force LuaForce|nil
local function destroy_visuals(summon, force)
  if summon.label then
    summon.label.destroy()
    summon.label = nil
  end
  if summon.circle_fx and summon.circle_fx.valid then
    summon.circle_fx.destroy()
  end
  summon.circle_fx = nil
  if summon.tag and summon.tag.valid then
    summon.tag.destroy()
  end
  summon.tag = nil
  if force then
    for _, player in ipairs(force.connected_players) do
      player.remove_alert({ type = defines.alert_type.custom, icon = { type = "item", name = summon.item } })
    end
  end
end

---A custom alert on the entity for every player of the force.
---@param force LuaForce
---@param entity LuaEntity
---@param summon table
---@param message LocalisedString
local function alert(force, entity, summon, message)
  for _, player in ipairs(force.connected_players) do
    player.add_custom_alert(entity, { type = "item", name = summon.item }, message, true)
  end
end

---@param summon table
---@param force LuaForce
local function update_health_bar(summon, force)
  local module = module_of(summon)
  local status = module and module.status and module.status(summon) or nil
  gui.update(force, { "nexus-bosses.bar-title", boss_name(summon.boss), { "nexus-bosses.stage-" .. cfg.CIRCLES[summon.circle].stage } },
    records.health_share(summon), status)
end

-- Ending ------------------------------------------------------------------------------------------------------------

---@param summon table
---@param force LuaForce|nil
local function cleanup(summon, force)
  destroy_visuals(summon, force)
  if force then
    gui.destroy(force)
  end
  unregister_death_events()
  storage.summon = nil
end

---Ends the summon without a victory.
---@param summon table
---@param message_key string key in the group nexus-bosses, whose first parameter is the name of the boss
---@param color Color
---@param options {refund: boolean|nil, keep_beacon: boolean|nil, params: LocalisedString[]|nil}
local function end_summon(summon, message_key, color, options)
  local force = force_of(summon)
  local beacon = summon.beacon
  if beacon and beacon.valid and not options.keep_beacon then
    beacon.destroy()
  end
  summon.beacon = nil
  local surface = game.get_surface(summon.surface_index)
  if options.refund and surface then
    give_back(surface, summon.position, summon.item, summon.quality, nil)
  end
  local module = module_of(summon)
  if module and module.release then
    module.release(summon)
  end
  cleanup(summon, force)
  if force then
    local message = { "nexus-bosses." .. message_key, boss_name(summon.boss) }
    for _, extra in ipairs(options.params or {}) do
      message[#message + 1] = extra
    end
    util.say(force, message, color)
  end
end

---@param summon table
---@param force LuaForce
---@param surface LuaSurface
local function victory(summon, force, surface)
  local boss = summon.boss
  local first = progress.mark_defeated(force, boss)
  local module = module_of(summon)
  if module and module.on_victory then
    module.on_victory(summon)
  end
  cleanup(summon, force)
  util.say(force, { first and "nexus-bosses.msg-boss-defeated" or "nexus-bosses.msg-boss-defeated-again", boss_name(boss) },
    util.COLORS.good)
  util.play(force, "victory")
  progress.drop_trophy(force, surface, boss, summon.last_position or summon.position)
  if summon.lair then
    bearing.lair_victory(force, surface, boss, summon.last_position or summon.position)
  end
  expedition.reveal_next(force, summon.last_position or summon.position)
  if boss == "storm-guardian" then
    progress.storm_guardian_fell(force)
  end
  progress.sync_unlocks(force, true)
  story.sync(force)
end

-- The boss appears ----------------------------------------------------------------------------------------------------

---@param summon table
---@param force LuaForce
---@param surface LuaSurface
local function complete_spawn(summon, force, surface)
  if summon.beacon and summon.beacon.valid then
    summon.beacon.destroy()
  end
  summon.beacon = nil
  destroy_visuals(summon, force)
  summon.phase = "active"
  summon.active_seconds = 0
  -- the pylon of the lair takes its share of the health of every boss that must die
  local share = summon.pylon_share or 0
  if share > 0 then
    for _, record in ipairs(summon.tracked) do
      if record.required and records.alive(record) then
        record.entity.health = record.entity.health * (1 - share)
      end
    end
  end

  local main = records.main(summon)
  local where = main and records.position(main) or summon.position
  summon.last_position = util.copy_position(where)
  local x, y = util.xy(where)
  util.say(force, { "nexus-bosses.arrive-" .. summon.boss }, util.COLORS.bad)
  util.say(force, { "nexus-bosses.msg-boss-appeared", boss_name(summon.boss), math.floor(x), math.floor(y), surface.name },
    util.COLORS.bad)
  util.play(force, "arrive-" .. summon.boss)
  if summon.boss == "storm-guardian" then
    util.play(force, "arrive-storm-guardian-stinger")
  end
  summon.music_index = 0
  summon.music_until = 0
  if summon.spawn_note == "closer" then
    util.say(force, { "nexus-bosses.msg-spawn-closer", math.floor(summon.spawn_distance) }, util.COLORS.warning)
  end
  for _, record in ipairs(summon.tracked) do
    if record.required and not record.segmented then
      alert(force, record.entity, summon, { "nexus-bosses.alert-boss", boss_name(summon.boss) })
      break
    end
  end
  update_health_bar(summon, force)
end

---@param summon table
---@param force LuaForce
---@param surface LuaSurface
local function bm_attempt(summon, force, surface)
  local state = summon.bm
  state.attempts = state.attempts + 1
  state.last_tick = game.tick
  -- below 0.9 the events make lesser monsters, which would pile up with every call
  nexus.refresh_evolution()
  state.error = bm.call_event(bm.set_of(summon.boss).event, surface, force)
end

---@param summon table
---@param surface LuaSurface
---@return boolean the boss is there
local function bm_collect(summon, surface)
  local state = summon.bm
  local found = bm.find_new(surface, state.names, state.snapshot)
  for _, entity in ipairs(found) do
    if not summon.by_unit[entity.unit_number] then
      bm.adopt(summon, surface, entity)
    end
  end
  return #found > 0
end

---@param summon table
---@param force LuaForce
---@param surface LuaSurface
local function launch(summon, force, surface)
  summon.phase = "spawning"
  summon.beacon.minable_flag = false
  summon.beacon.destructible = false
  update_visuals(summon)

  if summon.bm then
    local state = summon.bm
    state.snapshot = bm.snapshot(surface, state.names)
    bm.request_land(surface, force, bm.set_of(summon.boss).explore_chunks)
    bm_attempt(summon, force, surface)
    if bm_collect(summon, surface) then
      complete_spawn(summon, force, surface)
    end
    return
  end

  local ok, message_key = (module_of(summon) --[[@as table]]).spawn(summon, surface)
  if ok then
    complete_spawn(summon, force, surface)
  else
    end_summon(summon, message_key, util.COLORS.bad, { refund = true })
  end
end

-- Steps -----------------------------------------------------------------------------------------------------------

---@param summon table
---@param force LuaForce
---@param surface LuaSurface
local function step_countdown(summon, force, surface)
  if not summon.beacon.valid then
    end_summon(summon, "msg-cancel-lost", util.COLORS.bad, {})
    return
  end
  if not (storage.ignore_presence or util.count_present(force, surface) > 0) then
    if not summon.paused then
      summon.paused = true
      util.say(force, { "nexus-bosses.msg-countdown-paused" }, util.COLORS.warning)
      update_visuals(summon)
    end
    return
  end
  if summon.paused then
    summon.paused = false
    util.say(force, { "nexus-bosses.msg-countdown-resumed" }, util.COLORS.info)
  end
  summon.countdown = summon.countdown - 1
  update_visuals(summon)
  if summon.countdown <= 0 then
    launch(summon, force, surface)
    return
  end
  if summon.waves[summon.countdown] then
    local origin = spawn.precursor_wave(summon, surface)
    if origin then
      local x, y = util.xy(origin)
      util.say(force, { "nexus-bosses.msg-precursors", util.compass(summon.angle), math.floor(x), math.floor(y),
        surface.name }, util.COLORS.warning)
      util.play(force, "precursors")
    end
  end
  if summon.countdown % 10 == 0 or summon.countdown <= 5 then
    alert(force, summon.beacon, summon, { "nexus-bosses.alert-countdown", boss_name(summon.boss), summon.countdown })
    if summon.countdown == 10 or summon.countdown == 3 then
      util.play(force, "countdown")
    end
  end
end

---@param summon table
---@param force LuaForce
---@param surface LuaSurface
local function step_spawning(summon, force, surface)
  local state = summon.bm
  if bm_collect(summon, surface) then
    complete_spawn(summon, force, surface)
    return
  end
  state.window = state.window - 1
  if state.window <= 0 then
    end_summon(summon, "msg-fail-no-boss", util.COLORS.bad, { refund = true })
    return
  end
  -- Big Monsters may have found no place yet: the land may still be generating
  if game.tick - state.last_tick >= BM_RETRY_TICKS and util.count_present(force, surface) > 0 then
    bm_attempt(summon, force, surface)
    if bm_collect(summon, surface) then
      complete_spawn(summon, force, surface)
    end
  end
end

---@param summon table
---@param force LuaForce
---@param surface LuaSurface
local function step_active(summon, force, surface)
  records.refresh(summon)
  local alive, dead, gone = records.status(summon)
  if alive == 0 then
    if dead > 0 and gone == 0 then
      victory(summon, force, surface)
    else
      end_summon(summon, "msg-fail-vanished", util.COLORS.warning, { refund = true })
    end
    return
  end
  summon.active_seconds = summon.active_seconds + 1
  if game.tick >= summon.music_until then
    -- the tracks take turns while the boss lives
    summon.music_index = summon.music_index % #util.FIGHT_TRACKS + 1
    local track = util.FIGHT_TRACKS[summon.music_index] --[[@as {name: string, seconds: integer}]]
    force.play_music({ name = track.name, fade_in_duration = 120, fade_out_duration = 120 })
    summon.music_until = game.tick + track.seconds * 60
  end
  local module = module_of(summon)
  if module then
    if module.tick then
      module.tick(summon, surface, force)
    end
  else
    bm.tick(summon, surface)
  end
  local main = records.main(summon)
  local where = main and records.position(main)
  if where then
    summon.last_position = util.copy_position(where)
  end
  update_health_bar(summon, force)
end

---Once a second. Costs nothing while no summon is active.
function M.step()
  local summon = storage.summon
  if not summon then
    return
  end
  local force = force_of(summon)
  local surface = game.get_surface(summon.surface_index)
  -- the index of a deleted surface can be reused: it has to be Nexus still
  if not (force and surface and surface.name == cfg.PLANET) then
    end_summon(summon, "msg-aborted-world", util.COLORS.warning, {})
    return
  end
  if summon.phase == "countdown" then
    step_countdown(summon, force, surface)
  elseif summon.phase == "spawning" then
    step_spawning(summon, force, surface)
  else
    step_active(summon, force, surface)
  end
end

-- Events ----------------------------------------------------------------------------------------------------------

---@param event EventData.on_entity_died
on_entity_died = function(event)
  local summon = storage.summon
  local entity = event.entity
  if not summon or not entity.unit_number then
    return
  end
  if entity.unit_number == summon.beacon_unit then
    if summon.phase == "countdown" then
      end_summon(summon, "msg-cancel-destroyed", util.COLORS.bad, { keep_beacon = true })
    end
    return
  end
  local record = records.mark_dead(summon, entity.unit_number)
  if record and record.required then
    summon.last_position = util.copy_position(entity.position)
  end
end
M.on_entity_died = on_entity_died

---@param event EventData.on_segmented_unit_died
function M.on_segmented_unit_died(event)
  local summon = storage.summon
  if summon then
    records.mark_dead(summon, event.segmented_unit.unit_number)
  end
end

---A beacon was mined: during the countdown that cancels the summon (the miner keeps the item).
---@param entity LuaEntity
function M.on_beacon_mined(entity)
  local summon = storage.summon
  if summon and entity.unit_number == summon.beacon_unit and summon.phase == "countdown" then
    end_summon(summon, "msg-cancel-mined", util.COLORS.warning, { keep_beacon = true })
  end
end

---A beacon cannot start a summon: it is taken away and its item returned.
---@param entity LuaEntity
---@param player LuaPlayer|nil
---@param message LocalisedString
local function reject(entity, player, message)
  local surface, position, force = entity.surface, entity.position, util.force_of(entity)
  local item, quality = entity.name, entity.quality.name
  entity.destroy()
  give_back(surface, position, item, quality, player)
  util.say(player or force, message, util.COLORS.warning)
end

---A beacon was built by a player, a robot or a script, or cloned.
---@param entity LuaEntity
---@param player LuaPlayer|nil
function M.on_built(entity, player)
  local boss_id, charge = cfg.boss_of_beacon(entity.name)
  -- a mod may forward the build event of the same beacon
  if not boss_id or (storage.summon and storage.summon.beacon_unit == entity.unit_number) then
    return
  end
  local surface = entity.surface
  local force = util.force_of(entity)
  local boss = cfg.BOSSES[boss_id]

  if surface.name ~= cfg.PLANET then
    return reject(entity, player, { "nexus-bosses.msg-reject-surface" })
  elseif force.name == "enemy" or force.name == "neutral" then
    return reject(entity, player, { "nexus-bosses.msg-reject-force" })
  elseif storage.summon then
    return reject(entity, player, { "nexus-bosses.msg-reject-busy", boss_name(storage.summon.boss) })
  end

  local countdown = settings.global["nexus-bosses-countdown"].value --[[@as integer]]
  local id = storage.next_summon_id
  storage.next_summon_id = id + 1
  local summon = {
    id = id,
    boss = boss_id,
    circle = boss.circle,
    force = force.name,
    surface_index = surface.index,
    phase = "countdown",
    beacon = entity,
    beacon_unit = entity.unit_number,
    item = entity.name,
    quality = entity.quality.name,
    position = util.copy_position(entity.position),
    angle = math.random() * 2 * math.pi, -- the side the trial comes from
    countdown = countdown,
    countdown_total = countdown,
    waves = { [math.floor(countdown * 2 / 3)] = true, [math.floor(countdown / 3)] = true },
    paused = false,
    active_seconds = 0,
    tracked = {},
    by_unit = {},
    charge = charge,
    lair = bearing.in_lair(force.name, boss_id, entity.position),
    pylon_share = bearing.pylon_share(force.name, boss_id, entity.position),
  }
  summon.watch = { entity.name }
  if boss.kind == "bm" then
    summon.bm = { names = bm.boss_names(boss_id), attempts = 0, window = BM_WINDOW_SECONDS, snapshot = {}, last_tick = 0 }
    for _, name in ipairs(summon.bm.names) do
      summon.watch[#summon.watch + 1] = name
    end
  else
    for _, name in ipairs((OWN[boss_id] --[[@as table]]).watch) do
      summon.watch[#summon.watch + 1] = name
    end
  end
  storage.summon = summon
  register_death_events(summon)

  create_visuals(summon, force, surface)
  spawn.request_land(surface, summon.position)
  if summon.bm then
    -- the countdown is the time the map generator needs for the land the event walks through
    bm.request_land(surface, force, bm.set_of(boss_id).explore_chunks)
  end
  util.say(force, { "nexus-bosses.call-" .. boss_id }, util.COLORS.warning)
  util.say(force, { "nexus-bosses.msg-countdown-started", boss_name(boss_id), countdown, util.compass(summon.angle) },
    util.COLORS.warning)
  if summon.lair then
    util.say(force, { "nexus-bosses.msg-lair-fight", boss_name(boss_id),
      string.format("[item=%s,quality=%s]", cfg.trophy_name(boss_id), bearing.next_quality(force.name, boss_id)) },
      util.COLORS.good)
  end
  if charge > 0 then
    util.say(force, { "nexus-bosses.msg-beacon-charged", charge, cfg.CHARGES }, util.COLORS.good)
  end
  if summon.pylon_share > 0 then
    util.say(force, { "nexus-bosses.msg-pylon-weakens", boss_name(boss_id), math.floor(summon.pylon_share * 100) },
      util.COLORS.good)
  end
  util.play(force, "call")
end

-- Load and configuration -------------------------------------------------------------------------------------------

---Handlers registered at run time are not saved: bring back the one of the active summon.
function M.restore_events()
  local summon = storage.summon
  if summon and summon.watch then
    register_death_events(summon)
  end
end

function M.on_configuration_changed()
  local summon = storage.summon
  if summon and not (cfg.BOSSES[summon.boss] and summon.watch) then
    -- a summon of an older version of the mod: its prototypes may be gone
    storage.summon = nil
    unregister_death_events()
  elseif summon then
    -- 2.0 had no music, 2.2 no charge or lair
    summon.music_index = summon.music_index or 0
    summon.music_until = summon.music_until or 0
    summon.charge = summon.charge or 0
    summon.pylon_share = summon.pylon_share or 0
  end
  M.restore_events()
end

---Ends the active summon without a victory. For administrators and tests.
---@param destroy_bosses boolean|nil also destroy what the trial created
---@return boolean true when there was a summon
function M.abort(destroy_bosses)
  local summon = storage.summon
  if not summon then
    return false
  end
  local refund = summon.phase ~= "active"
  if destroy_bosses then
    for _, record in ipairs(summon.tracked) do
      if records.alive(record) and not record.hidden then
        record.entity.destroy()
      end
    end
    local territory = summon.devourer and summon.devourer.territory
    if territory and territory.valid then
      territory.destroy()
    end
  end
  end_summon(summon, "msg-aborted", util.COLORS.warning, { refund = refund })
  return true
end

---Plain data for the remote interface.
---@return table|nil
function M.snapshot()
  local summon = storage.summon
  if not summon then
    return nil
  end
  return {
    id = summon.id,
    boss = summon.boss,
    circle = summon.circle,
    force = summon.force,
    phase = summon.phase,
    paused = summon.paused,
    beacon_valid = summon.beacon ~= nil and summon.beacon.valid,
    beacon_position = util.copy_position(summon.position),
    angle = summon.angle,
    countdown_left = summon.countdown,
    countdown_total = summon.countdown_total,
    active_seconds = summon.active_seconds,
    tracked = records.snapshot(summon),
    health_share = records.health_share(summon),
    spawn_note = summon.spawn_note,
    charge = summon.charge,
    lair = summon.lair,
    pylon_share = summon.pylon_share,
    spawn_distance = summon.spawn_distance,
    bm = summon.bm and { attempts = summon.bm.attempts, window_left = summon.bm.window, last_error = summon.bm.error },
  }
end

return M
