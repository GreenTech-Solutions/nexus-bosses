-- The life of a summon: placement of a beacon, the countdown, the appearance of the boss, the victory.
--
-- phase "countdown"  the beacon stands, a label, a chart tag and an alarm mark it. Every second without a player of
--                    the force on Nexus (or with the debug switch off) the countdown waits; else it runs down (map setting "nexus-bosses-countdown", 60 s by default).
--                    Destroying or mining the beacon cancels the summon.
-- phase "spawning"   the countdown reached zero. The mod's own bosses are created at once. For a Big-Monsters boss
--                    the event is called and the surface is scanned for boss entities that were not there before; the
--                    call is repeated every two seconds while a player is on Nexus, for a window of 60 seconds (the
--                    event places its boss by walking through generated land and silently creates nothing when there is
--                    too little of it, so the land around the spawn of the force was requested from the map generator
--                    when the countdown started, see nb_bm.lua). The beacon is locked (neither mined nor damaged)
--                    until the boss appears; if nothing shows up the beacon is returned and the summon ends without
--                    victory.
-- phase "active"     the boss lives, the beacon is gone. The victory comes when every required entity has died
--                    (death events). Required entities that vanish without dying end the summon without victory.
-- Whatever ends a summon, `storage.summon` becomes nil, so a new beacon can always be placed.

local cfg = require("lib.nb_data")
local util = require("scripts.nb_util")
local records = require("scripts.nb_records")
local bm = require("scripts.nb_bm")
local nexus = require("scripts.nb_nexus")
local spawn = require("scripts.nb_spawn")
local progress = require("scripts.nb_progress")

local M = {}

local BM_WINDOW_SECONDS = 60
local BM_RETRY_TICKS = 120

---@param id string
---@return LocalisedString
local function boss_name(id)
  return { "nexus-bosses.boss-" .. id }
end

---@param summon table
---@return LuaForce|nil
local function force_of(summon)
  local force = game.forces[summon.force]
  if force and force.valid then
    return force
  end
  return nil
end

-- Items -----------------------------------------------------------------------------------------------------------

---Returns a beacon item to the builder, or drops it on the ground when there is nobody or no room.
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

---A beacon that cannot start a summon is taken away and its item returned.
---@param entity LuaEntity
---@param player LuaPlayer|nil
---@param message LocalisedString
local function reject(entity, player, message)
  local surface = entity.surface
  local position = entity.position
  local force = util.force_of(entity)
  local item = entity.name
  local quality = entity.quality and entity.quality.name or nil
  entity.destroy()
  give_back(surface, position, item, quality, player)
  if player and player.valid then
    util.say(player, message, util.COLORS.warning)
  else
    util.say(force, message, util.COLORS.warning)
  end
end

-- Death events -------------------------------------------------------------------------------------------------------

---The names of the entities whose death matters for the summon: the beacon, the required bosses.
---@param summon table
---@return table[] event filters
local function build_death_filters(summon)
  local names = { summon.item }
  for _, name in ipairs(cfg.BOSSES[summon.boss].watch or {}) do
    names[#names + 1] = name
  end
  if summon.bm then
    for _, name in ipairs(summon.bm.names) do
      names[#names + 1] = name
    end
  end
  local filters = {}
  for index, name in ipairs(names) do
    filters[index] = { filter = "name", name = name }
  end
  return filters
end

-- forward declaration: the handler is registered with the filters of the summon
local on_entity_died

---@param summon table
local function register_death_events(summon)
  script.on_event(defines.events.on_entity_died, on_entity_died, summon.death_filters)
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
  return { "nexus-bosses.label-countdown", math.max(summon.countdown, 0) }
end

---@param summon table
---@return string
local function marker_text(summon)
  return string.format("[item=%s] %d", summon.item, math.max(summon.countdown, 0))
end

---@param summon table
local function update_visuals(summon)
  if summon.label and summon.label.valid then
    summon.label.text = label_text(summon)
  end
  if summon.tag and summon.tag.valid and summon.countdown % 5 == 0 then
    summon.tag.text = marker_text(summon)
  end
end

---@param summon table
---@param force LuaForce
---@param surface LuaSurface
local function create_visuals(summon, force, surface)
  local position = summon.position
  pcall(function()
    force.chart(surface, { { position.x - 24, position.y - 24 }, { position.x + 24, position.y + 24 } })
    summon.tag = force.add_chart_tag(surface, {
      position = position,
      text = marker_text(summon),
      icon = { type = "item", name = summon.item },
    })
  end)
  summon.label = rendering.draw_text({
    text = label_text(summon),
    surface = surface,
    target = { entity = summon.beacon, offset = { 0, -2.4 } },
    forces = { force }, -- the label is for the force of the summon only
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
  if summon.tag and summon.tag.valid then
    summon.tag.destroy()
  end
  summon.tag = nil
  if force then
    for _, player in ipairs(force.connected_players) do
      pcall(function()
        player.remove_alert({ type = defines.alert_type.custom, icon = { type = "item", name = summon.item } })
      end)
    end
  end
end

---Sound and a custom alert on the beacon for every player of the force.
---@param summon table
---@param force LuaForce
---@param siren boolean
local function alarm(summon, force, siren)
  util.play(force, siren and util.SOUND_SIREN or util.SOUND_ALARM)
  local beacon = summon.beacon
  if beacon and beacon.valid then
    local message = { "nexus-bosses.alert-countdown", boss_name(summon.boss), math.max(summon.countdown, 0) }
    for _, player in ipairs(force.connected_players) do
      player.add_custom_alert(beacon, { type = "item", name = summon.item }, message, true)
    end
  end
end

-- Ending ------------------------------------------------------------------------------------------------------------

---@param summon table
---@param force LuaForce|nil
local function cleanup(summon, force)
  destroy_visuals(summon, force)
  unregister_death_events()
  storage.summon = nil
end

---Ends the summon without a victory.
---@param summon table
---@param message_key string key in the group nexus-bosses; its first parameter is the name of the boss
---@param color Color
---@param options {refund: boolean|nil, keep_beacon: boolean|nil, params: LocalisedString[]|nil} params: more parameters of the message
local function end_summon(summon, message_key, color, options)
  local force = force_of(summon)
  local beacon = summon.beacon
  if beacon and beacon.valid and not options.keep_beacon then
    beacon.destroy()
  end
  summon.beacon = nil
  if options.refund then
    local surface = game.get_surface(summon.surface_index)
    if surface and surface.valid then
      give_back(surface, summon.position, summon.item, summon.quality, nil)
    end
  end
  local released, release_error = pcall(spawn.release, summon)
  if not released then
    log("[nexus-bosses] cannot release what the trial of " .. summon.boss .. " set up: " .. tostring(release_error))
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
local function victory(summon, force)
  local boss = summon.boss
  local first = progress.mark_defeated(force, boss)
  spawn.on_victory(summon)
  util.say(force, { first and "nexus-bosses.msg-boss-defeated" or "nexus-bosses.msg-boss-defeated-again", boss_name(boss) },
    util.COLORS.good)
  util.play(force, util.SOUND_VICTORY)
  if boss == "storm-guardian" then
    progress.storm_guardian_fell(force)
  end
  progress.sync_unlocks(force, true)
  cleanup(summon, force)
end

-- The boss appears ----------------------------------------------------------------------------------------------------

---The beacon has done its job: it disappears and the fight begins.
---@param summon table
---@param force LuaForce
---@param surface LuaSurface
local function complete_spawn(summon, force, surface)
  if not summon.appear_position then
    local first = summon.tracked[1]
    if first and first.entity.valid then
      if first.segmented then
        summon.appear_position = summon.position
      else
        summon.appear_position = util.copy_position(first.entity.position)
      end
    end
  end
  local where = summon.appear_position or summon.position

  local beacon = summon.beacon
  if beacon and beacon.valid then
    beacon.destroy()
  end
  summon.beacon = nil
  destroy_visuals(summon, force)

  summon.phase = "active"
  summon.active_seconds = 0
  util.say(force, {
    "nexus-bosses.msg-boss-appeared",
    boss_name(summon.boss),
    math.floor(where.x),
    math.floor(where.y),
    surface.name,
  }, util.COLORS.bad)
  util.play(force, util.SOUND_SIREN)
  if summon.spawn_note == "closer" or summon.spawn_note == "closest" then
    util.say(force, { "nexus-bosses.msg-spawn-closer", math.floor(summon.spawn_distance or 0) }, util.COLORS.warning)
  end

  -- a custom alert on the first living entity that can carry one
  for _, record in ipairs(summon.tracked) do
    if not record.segmented and record.entity.valid then
      local message = { "nexus-bosses.alert-boss", boss_name(summon.boss) }
      for _, player in ipairs(force.connected_players) do
        player.add_custom_alert(record.entity, { type = "item", name = summon.item }, message, true)
      end
      break
    end
  end
end

---One call of the Big-Monsters event; the result is looked for by the caller.
---@param summon table
---@param force LuaForce
---@param surface LuaSurface
local function bm_attempt(summon, force, surface)
  local state = summon.bm
  state.attempts = state.attempts + 1
  state.last_tick = game.tick
  -- Big-Monsters makes its big bosses only from an evolution of 0.9 on (below that its events create ordinary
  -- worms, giants and saucers, which are not the boss of this summon and would pile up with every call): the evolution
  -- of Nexus is pinned once a minute, and here again before every call
  local pinned, pin_error = pcall(nexus.refresh_evolution)
  if not pinned then
    log("[nexus-bosses] cannot pin the evolution before the call of Big-Monsters: " .. tostring(pin_error))
  end
  local ok, err = bm.call_event(state.event, surface, force)
  if ok then
    state.error = nil
  else
    state.error = err
  end
end

---Records the boss entities that appeared since the snapshot.
---@param summon table
---@param surface LuaSurface
---@return integer number of new records
local function bm_collect(summon, surface)
  local state = summon.bm
  local added = 0
  for _, entity in ipairs(bm.find_new(surface, state.names, state.snapshot)) do
    if not summon.by_unit[entity.unit_number] then
      records.add(summon, entity, entity.name, true, "boss")
      added = added + 1
    end
  end
  return added
end

---The countdown reached zero.
---@param summon table
---@param force LuaForce
---@param surface LuaSurface
local function launch(summon, force, surface)
  summon.phase = "spawning"
  local beacon = summon.beacon
  if beacon and beacon.valid then
    beacon.minable_flag = false
    beacon.destructible = false
  end
  update_visuals(summon)
  alarm(summon, force, true)

  if summon.bm then
    local state = summon.bm
    state.snapshot = bm.snapshot(surface, state.names)
    state.window = BM_WINDOW_SECONDS
    bm.request_land(surface, force, state.explore)
    bm_attempt(summon, force, surface)
    if bm_collect(summon, surface) > 0 then
      complete_spawn(summon, force, surface)
    end
    return
  end

  -- a failure inside the spawning code must not crash the game: log it and give the beacon back
  local called, ok, message_key = pcall(spawn.spawn, summon, surface)
  if not called then
    log("[nexus-bosses] spawning " .. summon.boss .. " failed: " .. tostring(ok))
    ok = false
    message_key = "msg-fail-position"
  end
  if ok then
    complete_spawn(summon, force, surface)
  else
    end_summon(summon, message_key or "msg-fail-position", util.COLORS.bad, { refund = true })
  end
end

-- Steps -----------------------------------------------------------------------------------------------------------

---@param summon table
---@param force LuaForce
---@param surface LuaSurface
local function step_countdown(summon, force, surface)
  local beacon = summon.beacon
  if not (beacon and beacon.valid) then
    end_summon(summon, "msg-cancel-lost", util.COLORS.bad, {})
    return
  end
  local present = storage.ignore_presence or util.count_present(force, surface) > 0
  if not present then
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
  elseif summon.countdown % 10 == 0 or summon.countdown <= 5 then
    alarm(summon, force, false)
  end
end

---@param summon table
---@param force LuaForce
---@param surface LuaSurface
local function step_spawning(summon, force, surface)
  local state = summon.bm
  if not state then
    end_summon(summon, "msg-fail-position", util.COLORS.bad, { refund = true })
    return
  end
  if bm_collect(summon, surface) > 0 then
    complete_spawn(summon, force, surface)
    return
  end
  state.window = state.window - 1
  if state.window <= 0 then
    end_summon(summon, "msg-fail-no-boss", util.COLORS.bad, { refund = true, params = { state.explore * 32 } })
    return
  end
  -- Big-Monsters may have found no place (it walks a random line through generated chunks and the land may still be
  -- generating): try again every two seconds for the whole window while a player is on Nexus, which its event needs
  -- anyway
  if game.tick - state.last_tick >= BM_RETRY_TICKS and util.count_present(force, surface) > 0 then
    bm_attempt(summon, force, surface)
    if bm_collect(summon, surface) > 0 then
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
      victory(summon, force)
    else
      end_summon(summon, "msg-fail-vanished", util.COLORS.warning, {})
    end
    return
  end
  summon.active_seconds = summon.active_seconds + 1
  spawn.tick(summon, surface)
end

---@param summon table
local function step_summon(summon)
  local force = force_of(summon)
  local surface = game.get_surface(summon.surface_index)
  -- the index of a deleted surface can be reused: the surface has to be Nexus still
  if not (force and surface and surface.valid and surface.name == cfg.PLANET) then
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

---An error inside the mod must not crash the game, once a second for good: it is logged, said in the chat, and
---the active summon is ended (the beacon comes back) so the game goes on and a new beacon can be placed.
---@param where string
---@param err any
local function fail(where, err)
  log("[nexus-bosses] error in " .. where .. ": " .. tostring(err))
  game.print({ "nexus-bosses.msg-internal-error" }, { color = util.COLORS.bad })
  local summon = storage.summon
  if summon then
    local ended = pcall(end_summon, summon, "msg-aborted", util.COLORS.bad, { refund = summon.phase ~= "active" })
    if not ended then
      storage.summon = nil
      pcall(unregister_death_events)
    end
  end
end

---Called once a second (on_nth_tick 60). Costs nothing while no summon is active.
function M.step()
  local summon = storage.summon
  if not summon then
    return
  end
  local ok, err = pcall(step_summon, summon)
  if not ok then
    fail("the step of the summon", err)
  end
end

-- Events ----------------------------------------------------------------------------------------------------------

---@param event EventData.on_entity_died
local function handle_entity_died(event)
  local summon = storage.summon
  if not summon then
    return
  end
  local entity = event.entity
  if not (entity and entity.valid) then
    return
  end
  local number = entity.unit_number
  if not number then
    return
  end
  if number == summon.beacon_unit and summon.phase == "countdown" then
    end_summon(summon, "msg-cancel-destroyed", util.COLORS.bad, { keep_beacon = true })
    return
  end
  records.mark_dead(summon, number)
end

---@param event EventData.on_entity_died
on_entity_died = function(event)
  local ok, err = pcall(handle_entity_died, event)
  if not ok then
    fail("the death event", err)
  end
end
M.on_entity_died = on_entity_died

---A segmented unit (the Host Worm) died.
---@param event EventData.on_segmented_unit_died
function M.on_segmented_unit_died(event)
  local summon = storage.summon
  local unit = event.segmented_unit
  if summon and unit then
    local ok, err = pcall(records.mark_dead, summon, unit.unit_number)
    if not ok then
      fail("the death event of a segmented unit", err)
    end
  end
end

---@param entity LuaEntity
local function handle_beacon_mined(entity)
  local summon = storage.summon
  if not (summon and entity and entity.valid) then
    return
  end
  if entity.unit_number == summon.beacon_unit and summon.phase == "countdown" then
    end_summon(summon, "msg-cancel-mined", util.COLORS.warning, { keep_beacon = true })
  end
end

---A beacon was mined by a player or a robot: during the countdown that cancels the summon (the miner keeps the item).
---@param entity LuaEntity
function M.on_beacon_mined(entity)
  local ok, err = pcall(handle_beacon_mined, entity)
  if not ok then
    fail("the mining of a beacon", err)
  end
end

---@param entity LuaEntity
---@param player LuaPlayer|nil
local function handle_built(entity, player)
  if not (entity and entity.valid) then
    return
  end
  local boss_id = cfg.boss_of_beacon(entity.name)
  if not boss_id then
    return
  end
  -- the same beacon reported twice (a mod forwards the build event)
  if storage.summon and storage.summon.beacon_unit == entity.unit_number then
    return
  end
  local surface = entity.surface
  local force = util.force_of(entity)
  local boss = cfg.BOSSES[boss_id]

  local reason
  if surface.name ~= cfg.PLANET then
    reason = { "nexus-bosses.msg-reject-surface" }
  elseif force.name == "enemy" or force.name == "neutral" then
    reason = { "nexus-bosses.msg-reject-force" }
  elseif storage.summon then
    reason = { "nexus-bosses.msg-reject-busy", boss_name(storage.summon.boss) }
  elseif boss.kind == "bm" and not bm.available() then
    reason = { "nexus-bosses.msg-reject-no-bm" }
  end
  local names = boss.kind == "bm" and bm.boss_names(boss_id) or {}
  if not reason and boss.kind == "bm" and #names == 0 then
    reason = { "nexus-bosses.msg-reject-bm-names" }
  end
  if reason then
    reject(entity, player, reason)
    return
  end

  local id = storage.next_summon_id
  storage.next_summon_id = id + 1
  -- the map setting "nexus-bosses-countdown", read when the beacon is lit
  local countdown = util.countdown_seconds()
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
    quality = entity.quality and entity.quality.name or nil,
    position = util.copy_position(entity.position),
    countdown = countdown,
    countdown_total = countdown,
    paused = false,
    active_seconds = 0,
    tracked = {},
    by_unit = {},
    start_tick = game.tick,
  }
  if boss.kind == "bm" then
    local set = cfg.BM_SETS[boss_id]
    summon.bm = {
      event = set.event,
      names = names,
      attempts = 0,
      window = BM_WINDOW_SECONDS,
      snapshot = {},
      last_tick = game.tick,
      explore = set.explore_chunks,
    }
  end
  summon.death_filters = build_death_filters(summon)
  storage.summon = summon
  register_death_events(summon)

  create_visuals(summon, force, surface)
  spawn.request_spawn_land(surface, summon.position)
  if summon.bm then
    -- the countdown is the time the map generator needs for the land that the event walks through
    bm.request_land(surface, force, summon.bm.explore)
  end
  util.say(force, { "nexus-bosses.msg-countdown-started", boss_name(boss_id), countdown }, util.COLORS.warning)
  alarm(summon, force, false)
end

---A beacon was built by a player, a robot, a script or cloned.
---@param entity LuaEntity
---@param player LuaPlayer|nil
function M.on_built(entity, player)
  local ok, err = pcall(handle_built, entity, player)
  if not ok then
    fail("the building of a beacon", err)
  end
end

-- Load and configuration -------------------------------------------------------------------------------------------

---Event handlers registered at run time are not saved: bring back the one of the active summon.
function M.restore_events()
  local summon = storage.summon
  if summon and summon.death_filters then
    register_death_events(summon)
  end
end

function M.on_configuration_changed()
  M.restore_events()
end

---Ends the active summon without a victory. For administrators and tests.
---@param destroy_bosses boolean|nil also destroy the entities of the boss
---@return boolean true when there was a summon
function M.abort(destroy_bosses)
  local summon = storage.summon
  if not summon then
    return false
  end
  if destroy_bosses then
    for _, record in ipairs(summon.tracked) do
      if record.entity and record.entity.valid then
        record.entity.destroy()
      end
    end
    if summon.lair then
      for _, turret in ipairs(summon.lair.turrets) do
        if turret.valid then
          turret.destroy()
        end
      end
    end
    if summon.territory and summon.territory.valid then
      summon.territory.destroy()
    end
  end
  end_summon(summon, "msg-aborted", util.COLORS.warning, { refund = summon.phase ~= "active" })
  return true
end

return M
