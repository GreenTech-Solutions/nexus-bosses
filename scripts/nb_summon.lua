-- The life of a summon.
--
-- "countdown"  the beacon stands, marked by a label, a map tag and alerts. Each second with a player of the force on
--              Nexus the countdown runs down (map setting, 60 s by default); without one it waits. At two thirds and
--              one third of it a precursor wave comes for the beacon from the side the boss will come from. Losing or
--              picking up the beacon cancels the summon.
-- "spawning"   the countdown is over and the beacon is locked while the boss module creates its entities.
-- "active"     the beacon is gone and the fight is on. The victory comes when every required entity has died.
-- Whatever ends a summon, storage.summon becomes nil, so a new beacon can be lit.

local cfg = require("lib.nb_data")
local util = require("scripts.nb_util")
local records = require("scripts.nb_records")
local spawn = require("scripts.nb_spawn")
local progress = require("scripts.nb_progress")
local gui = require("scripts.nb_gui")
local resistance = require("scripts.nb_resist")
local expedition = require("scripts.nb_expedition")
local bearing = require("scripts.nb_bearing")
local story = require("scripts.nb_story")
local vault = require("scripts.nb_vault")

local M = {}
local UNDEFENDED_SECONDS = 60

---@class NbPending
---@field at integer
---@field kind string
---@field data table
---@field entities LuaEntity[]|nil

---@class NbSummonRender
---@field render LuaRenderObject
---@field radius number
---@field start_tick integer
---@field end_tick integer

---@class NbTracked
---@field entity LuaEntity|LuaSegmentedUnit
---@field name string
---@field unit_number uint64
---@field required boolean
---@field role string
---@field segmented boolean
---@field initial number
---@field hidden boolean
---@field hidden_health number|nil
---@field dead boolean
---@field gone boolean
---@field death_position MapPosition|nil
---@field death_max_health number|nil

---@class NbSummon
---@field id integer
---@field boss string
---@field circle integer
---@field force string
---@field surface_index integer
---@field phase "countdown"|"spawning"|"active"
---@field beacon LuaEntity|nil
---@field beacon_unit uint64
---@field item string
---@field quality string
---@field position MapPosition
---@field angle number
---@field countdown integer
---@field countdown_total integer
---@field waves table<integer, boolean>
---@field paused boolean
---@field active_seconds integer
---@field undefended integer|nil
---@field tracked NbTracked[]
---@field by_unit table<uint64, NbTracked>
---@field watch string[]
---@field pending NbPending[]
---@field renders NbSummonRender[]
---@field charge integer
---@field lair boolean
---@field weaken number
---@field frequency number
---@field pylon_share number|nil legacy 2.x field cleared when configuration changes
---@field label LuaRenderObject|nil
---@field circle_fx LuaRenderObject|nil
---@field tag LuaCustomChartTag|nil
---@field variant string|nil
---@field variant_entity string|nil
---@field spawn_note string|nil
---@field spawn_distance number|nil
---@field last_position MapPosition|nil
---@field music_index integer|nil
---@field music_until integer|nil
---@field health_bar {status: LocalisedString|nil, resist: LocalisedString|nil}|nil
---@field queen table|nil
---@field watcher table|nil
---@field spidertron table|nil
---@field maws table|nil
---@field colossus table|nil
---@field hulk table|nil
---@field guardian table|nil
---@field devourer table|nil
---@field commander table|nil

-- Boss module contract:
--   spawn(summon, surface) -> success, failure_message_key: create the required boss records
--   tick(summon, surface, force): advance the boss mechanics once per second
--   status(summon) -> LocalisedString|nil: describe the mechanic for the fight bar
--   on_victory(summon), release(summon): clean up module-owned state at the matching end
-- Optional hooks:
--   prepare(summon): finish summon setup before death events are registered and messages are sent
--   countdown_note(summon) -> LocalisedString|nil: append a boss-specific countdown message
--   snapshot(summon) -> table|nil: expose plain module state as snapshot.boss_state
--   on_pending(summon, surface, force, entry): execute an expired telegraph
--   on_damaged(summon, event): handle damage to a watched entity
-- Every relevant entity name belongs in watch. Every entity created or adopted by a module must be recorded with
-- records.add(summon, entity, required, role); retain the LuaEntity reference instead of looking it up by unit number.
local OWN = {
  ["arachnid-queen"] = { module = require("scripts.bosses.arachnid-queen"), watch = { cfg.QUEEN } },
  ["watcher"] = {
    module = require("scripts.bosses.watcher"), watch = { cfg.WATCHER, cfg.WATCHER_DRONE },
  },
  ["rogue-spidertron"] = { module = require("scripts.bosses.rogue-spidertron"), watch = { cfg.SPIDERTRON } },
  ["twin-maws"] = { module = require("scripts.bosses.twin-maws"), watch = { cfg.MAW_FIRE, cfg.MAW_ACID } },
  ["colossus"] = { module = require("scripts.bosses.colossus"), watch = {} },
  ["last-commander"] = {
    module = require("scripts.bosses.last-commander"), watch = { cfg.COMMANDER },
  },
  ["plague-hulk"] = { module = require("scripts.bosses.plague-hulk"), watch = { cfg.HULK } },
  ["storm-guardian"] = { module = require("scripts.bosses.storm-guardian"), watch = { cfg.GUARDIAN } },
  ["devourer"] = { module = require("scripts.bosses.devourer"), watch = {} }, -- on_segmented_unit_died
}

---@param id string
---@return LocalisedString
local function boss_name(id)
  return { "nexus-bosses.boss-" .. id }
end

---@param summon NbSummon
---@return LocalisedString
local function title_name(summon)
  if summon.variant_entity then
    return { "entity-name." .. summon.variant_entity }
  end
  return boss_name(summon.boss)
end

---@param summon NbSummon
---@return table? # the module of an own boss
local function module_of(summon)
  local own = OWN[summon.boss]
  return own and own.module
end

---@param summon NbSummon
---@param force LuaForce
---@param surface LuaSurface
local function precursor_wave(summon, force, surface)
  local origin = spawn.precursor_wave(summon, surface)
  if origin then
    local x, y = util.xy(origin)
    util.say(force, { "nexus-bosses.msg-precursors", util.compass(summon.angle), math.floor(x), math.floor(y),
      surface.name }, util.COLORS.warning)
    util.play(force, "precursors")
  end
end

---@param summon NbSummon
---@return string
local function main_entity(summon)
  return summon.variant_entity or cfg.BOSSES[summon.boss].entity
end

---@param summon NbSummon
---@return LocalisedString
local function resistance_caption(summon)
  local entities = cfg.BOSSES[summon.boss].entities
  if not entities then
    return resistance.caption(main_entity(summon))
  end
  ---@type LocalisedString
  local caption = { "" }
  for index, name in ipairs(entities) do
    if index > 1 then
      caption[#caption + 1] = " "
    end
    caption[#caption + 1] = { "", { "entity-name." .. name }, ": ", resistance.caption(name) }
  end
  return caption --[[@as LocalisedString]]
end

---@param summon NbSummon
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

---@param summon NbSummon
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

---@param summon NbSummon
---@return LocalisedString
local function label_text(summon)
  if summon.phase == "spawning" then
    return { "nexus-bosses.label-spawning" }
  elseif summon.paused then
    return { "nexus-bosses.label-paused" }
  end
  return { "nexus-bosses.label-countdown", summon.countdown }
end

---@param summon NbSummon
local function update_visuals(summon)
  if summon.label and summon.label.valid then
    summon.label.text = label_text(summon)
  end
  if summon.tag and summon.tag.valid and summon.countdown % 5 == 0 then
    summon.tag.text = string.format("[item=%s] %d", summon.item, summon.countdown)
  end
end

---@param summon NbSummon
---@param force LuaForce
---@param surface LuaSurface
local function create_visuals(summon, force, surface)
  local beacon = assert(summon.beacon)
  local x, y = util.xy(summon.position)
  force.chart(surface, { { x - 24, y - 24 }, { x + 24, y + 24 } })
  summon.tag = force.add_chart_tag(surface, {
    position = summon.position,
    text = string.format("[item=%s] %d", summon.item, summon.countdown),
    icon = { type = "item", name = summon.item },
  })
  local tint = cfg.CIRCLES[summon.circle].color
  summon.circle_fx = rendering.draw_animation({
    animation = "nexus-bosses-summon-circle",
    target = beacon,
    surface = surface,
    tint = tint,
    render_layer = "lower-object",
  })
  summon.label = rendering.draw_text({
    text = label_text(summon),
    surface = surface,
    target = { entity = beacon, offset = { 0, -2.4 } },
    forces = { force },
    color = util.COLORS.warning,
    scale = 1.3,
    alignment = "center",
    vertical_alignment = "middle",
  })
end

---@param summon NbSummon
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
---@param summon NbSummon
---@param message LocalisedString
local function alert(force, entity, summon, message)
  for _, player in ipairs(force.connected_players) do
    player.add_custom_alert(entity, { type = "item", name = summon.item }, message, true)
  end
end

---@param summon NbSummon
---@param force LuaForce
local function update_health_bar(summon, force)
  local module = module_of(summon)
  local status = summon.undefended and { "nexus-bosses.status-undefended", UNDEFENDED_SECONDS - summon.undefended }
    or (module and module.status and module.status(summon) or nil)
  local resist = expedition.has_log(summon.force, summon.boss) and resistance_caption(summon) or nil
  summon.health_bar = { status = status, resist = resist }
  gui.update(force, { "nexus-bosses.bar-title", title_name(summon), { "nexus-bosses.stage-" .. cfg.CIRCLES[summon.circle].stage } },
    records.health_share(summon), status, resist)
end

---@param summon NbSummon
---@param surface LuaSurface
---@param force LuaForce
---@return boolean
local function has_defence(summon, surface, force)
  if #spawn.targets(surface, summon, summon.position, cfg.DEFENCE_RADIUS, { military = true, claimed = false }) > 0 then
    return true
  end
  for _, player in pairs(force.players) do
    local character = player.character
    if character and character.valid and character.surface_index == surface.index
      and character.health and character.health > 0
      and util.distance(character.position, summon.position) <= cfg.DEFENCE_RADIUS then
      return true
    end
  end
  return false
end

---@param summon NbSummon
---@param surface LuaSurface
local function destroy_required_entities(summon, surface)
  for _, record in ipairs(summon.tracked) do
    if record.required and records.alive(record) and not record.hidden and record.entity.valid then
      local position = records.position(record)
      if position then
        if record.name == cfg.WATCHER then
          surface.create_entity({ name = "big-explosion", position = position })
        else
          util.burrow(surface, position)
        end
      end
      record.entity.destroy()
    end
  end
end

-- Ending ------------------------------------------------------------------------------------------------------------

---@param summon NbSummon
---@param force LuaForce|nil
local function cleanup(summon, force)
  destroy_visuals(summon, force)
  for _, entry in ipairs(summon.renders or {}) do
    local render = entry.render
    if render and render.valid then
      render.destroy()
    end
  end
  summon.renders = {}
  summon.pending = {}
  if force then
    gui.destroy(force)
  end
  unregister_death_events()
  storage.summon = nil
end

---Ends the summon without a victory.
---@param summon NbSummon
---@param message_key string key in the group nexus-bosses, whose first parameter is the name of the boss
---@param color Color
---@param options {refund: boolean|nil, keep_beacon: boolean|nil, params: LocalisedString[]|nil, destroy_required: boolean|nil}
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
  if options.destroy_required and surface then
    destroy_required_entities(summon, surface)
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

---@param summon NbSummon
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
    bearing.lair_victory(force, surface, boss, summon.last_position or summon.position, summon.weaken or 0)
    vault.earn(force, "lair")
  end
  expedition.reveal_next(force, summon.last_position or summon.position)
  if boss == "storm-guardian" then
    progress.storm_guardian_fell(force)
  end
  progress.sync_unlocks(force, true)
  story.sync(force)
  vault.sync(force)
end

-- The boss appears ----------------------------------------------------------------------------------------------------

---@param summon NbSummon
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
  if summon.lair then
    precursor_wave(summon, force, surface)
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
    local spawn_distance = summon.spawn_distance or 0
    util.say(force, { "nexus-bosses.msg-spawn-closer", math.floor(spawn_distance) }, util.COLORS.warning)
  end
  for _, record in ipairs(summon.tracked) do
    if record.required and not record.segmented then
      alert(force, record.entity --[[@as LuaEntity]], summon,
        { "nexus-bosses.alert-boss", boss_name(summon.boss) })
      break
    end
  end
  update_health_bar(summon, force)
end

---@param summon NbSummon
local function clear_next_angle(summon)
  local by_boss = storage.next_angle[summon.force]
  if not by_boss then
    return
  end
  by_boss[summon.boss] = nil
  if next(by_boss) == nil then
    storage.next_angle[summon.force] = nil
  end
end

-- Steps -----------------------------------------------------------------------------------------------------------

---@param summon NbSummon
---@param force LuaForce
---@param surface LuaSurface
local function step_countdown(summon, force, surface)
  local beacon = summon.beacon
  if not (beacon and beacon.valid) then
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
    clear_next_angle(summon)
    summon.phase = "spawning"
    beacon.minable_flag = false
    beacon.destructible = false
    update_visuals(summon)
    local ok, message_key = (module_of(summon) --[[@as table]]).spawn(summon, surface)
    if ok then
      complete_spawn(summon, force, surface)
    else
      end_summon(summon, message_key, util.COLORS.bad, { refund = true })
    end
    return
  end
  if summon.waves[summon.countdown] then
    precursor_wave(summon, force, surface)
  end
  if summon.countdown % 10 == 0 or summon.countdown <= 5 then
    alert(force, beacon, summon, { "nexus-bosses.alert-countdown", boss_name(summon.boss), summon.countdown })
    if summon.countdown == 10 or summon.countdown == 3 then
      util.play(force, "countdown")
    end
  end
end

---@param summon NbSummon
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
  if has_defence(summon, surface, force) then
    if summon.undefended then
      summon.undefended = nil
      util.say(force, { "nexus-bosses.msg-trial-defended", boss_name(summon.boss) }, util.COLORS.good)
    end
  else
    summon.undefended = (summon.undefended or 0) + 1
    if summon.undefended == 1 then
      util.say(force, { "nexus-bosses.msg-trial-undefended", boss_name(summon.boss) }, util.COLORS.warning)
    end
    if summon.undefended >= UNDEFENDED_SECONDS then
      end_summon(summon, "msg-trial-lost", util.COLORS.bad, { destroy_required = true })
      return
    end
  end
  if game.tick >= summon.music_until then
    -- the tracks take turns while the boss lives
    local music_index = summon.music_index or 0
    summon.music_index = (music_index % #util.FIGHT_TRACKS + 1) --[[@as integer]]
    local track = util.FIGHT_TRACKS[summon.music_index] --[[@as {name: string, seconds: integer}]]
    force.play_music({ name = track.name, fade_in_duration = 120, fade_out_duration = 120 })
    summon.music_until = game.tick + track.seconds * 60
  end
  local module = module_of(summon)
  if module and module.tick then
    module.tick(summon, surface, force)
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
  else
    step_active(summon, force, surface)
  end
end

---Runs attacks whose telegraphs have expired. Called every ten ticks.
---@param tick integer
function M.on_pending(tick)
  local summon = storage.summon
  if not summon then
    return
  end
  local renders = summon.renders or {}
  summon.renders = renders
  for index = #renders, 1, -1 do
    local entry = renders[index]
    local render = entry.render
    if render and render.valid then
      if entry.radius and entry.start_tick and entry.end_tick then
        local duration = entry.end_tick - entry.start_tick
        local fill = duration > 0 and math.min(1, (tick - entry.start_tick) / duration) or 1
        render.radius = math.max(0.1, entry.radius * fill)
      end
    else
      table.remove(renders, index)
    end
  end
  if summon.phase ~= "active" then
    return
  end
  local queue = summon.pending or {}
  local due, remaining = {}, {}
  for _, entry in ipairs(queue) do
    if entry.at <= tick then
      due[#due + 1] = entry
    else
      remaining[#remaining + 1] = entry
    end
  end
  if #due == 0 then
    return
  end
  summon.pending = remaining

  local force = force_of(summon)
  local surface = game.get_surface(summon.surface_index)
  local module = module_of(summon)
  local alive = records.status(summon)
  if not (alive > 0 and force and surface and surface.name == cfg.PLANET and module and module.on_pending) then
    return
  end
  for _, entry in ipairs(due) do
    local current_summon = storage.summon
    if current_summon ~= summon then
      return
    end
    module.on_pending(summon, surface, force, entry)
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
  if record then
    record.death_position = util.copy_position(entity.position)
    record.death_max_health = entity.max_health
    if record.required then
      summon.last_position = util.copy_position(entity.position)
    end
  end
end

---@param event EventData.on_segmented_unit_died
function M.on_segmented_unit_died(event)
  local summon = storage.summon
  if summon then
    records.mark_dead(summon, event.segmented_unit.unit_number)
  end
end

---@param event EventData.on_entity_damaged
function M.on_damaged(event)
  local summon = storage.summon
  local entity = event.entity
  if not (summon and entity.unit_number) then
    return
  end
  local record = summon.by_unit[entity.unit_number]
  if not (record and record.entity == entity) then
    return
  end
  local module = module_of(summon)
  if module and module.on_damaged then
    module.on_damaged(summon, event)
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

  local countdown = math.floor((storage.countdown_override or settings.global["nexus-bosses-countdown"].value) --[[@as number]])
  local id = storage.next_summon_id
  storage.next_summon_id = id + 1
  storage.next_angle = storage.next_angle or {}
  local next_angles = storage.next_angle[force.name]
  if not next_angles then
    next_angles = {}
    storage.next_angle[force.name] = next_angles
  end
  local angle = next_angles[boss_id]
  if angle == nil then
    angle = math.random() * 2 * math.pi
    next_angles[boss_id] = angle
  end
  local lair = bearing.in_lair(force.name, boss_id, entity.position)
  local weaken = bearing.pylon_weaken(force.name, boss_id, entity.position)
  local beacon_unit = assert(entity.unit_number)
  ---@type NbSummon
  local summon = {
    id = id,
    boss = boss_id,
    circle = boss.circle,
    force = force.name,
    surface_index = surface.index,
    phase = "countdown",
    beacon = entity,
    beacon_unit = beacon_unit,
    item = entity.name,
    quality = entity.quality.name,
    position = util.copy_position(entity.position),
    angle = angle, -- the side the trial comes from
    countdown = countdown,
    countdown_total = countdown,
    waves = { [math.floor(countdown * 2 / 3)] = true, [math.floor(countdown / 3)] = true },
    paused = false,
    active_seconds = 0,
    tracked = {},
    by_unit = {},
    watch = { entity.name },
    pending = {},
    renders = {},
    charge = charge,
    lair = lair,
    weaken = weaken,
    frequency = lair and bearing.lair_frequency(force.name, boss_id) or 1,
  }
  for _, name in ipairs((OWN[boss_id] --[[@as table]]).watch) do
    summon.watch[#summon.watch + 1] = name
  end
  local module = module_of(summon)
  if module and module.prepare then
    module.prepare(summon)
  end
  storage.summon = summon
  register_death_events(summon)

  create_visuals(summon, force, surface)
  spawn.request_land(surface, summon.position)
  util.say(force, { "nexus-bosses.call-" .. boss_id }, util.COLORS.warning)
  util.say(force, { "nexus-bosses.msg-countdown-started", boss_name(boss_id), countdown, util.compass(summon.angle) },
    util.COLORS.warning)
  local countdown_note = module and module.countdown_note and module.countdown_note(summon) or nil
  if countdown_note then
    util.say(force, countdown_note, util.COLORS.warning)
  end
  if summon.lair then
    local trophy_quality = bearing.next_quality(force.name, boss_id)
    if (summon.weaken or 0) > 0 then
      trophy_quality = assert(bearing.pylon_quality(force.name, boss_id))
    end
    util.say(force, { "nexus-bosses.msg-lair-fight", boss_name(boss_id),
      string.format("[item=%s,quality=%s]", cfg.trophy_name(boss_id), trophy_quality) },
      util.COLORS.good)
  end
  if charge > 0 then
    util.say(force, { "nexus-bosses.msg-beacon-charged", charge, cfg.CHARGES }, util.COLORS.good)
  end
  if summon.weaken > 0 then
    util.say(force, { "nexus-bosses.msg-pylon-weakens", boss_name(boss_id), math.floor(summon.weaken * 100) },
      util.COLORS.good)
  end
  util.play(force, "call")
end

-- Load and configuration -------------------------------------------------------------------------------------------

function M.init()
  storage.next_angle = storage.next_angle or {}
  local summon = storage.summon
  if summon and summon.phase == "countdown" then
    local by_boss = storage.next_angle[summon.force] or {}
    by_boss[summon.boss] = by_boss[summon.boss] or summon.angle
    storage.next_angle[summon.force] = by_boss
  end
  local colossus = OWN.colossus.module
  if colossus.init then
    colossus.init()
  end
end

---@param source_name string
---@param destination LuaForce
function M.on_forces_merged(source_name, destination)
  storage.next_angle = storage.next_angle or {}
  local source = storage.next_angle[source_name]
  if source then
    local target = storage.next_angle[destination.name] or {}
    for boss_id, angle in pairs(source) do
      if target[boss_id] == nil then
        target[boss_id] = angle
      end
    end
    storage.next_angle[destination.name] = next(target) and target or nil
  end
  storage.next_angle[source_name] = nil
  local colossus = OWN.colossus.module
  if colossus.on_forces_merged then
    colossus.on_forces_merged(source_name, destination)
  end
end

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
    summon.weaken = summon.weaken or 0
    summon.frequency = summon.frequency or 1
    summon.pylon_share = nil
    summon.pending = summon.pending or {}
    summon.renders = summon.renders or {}
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
  local module = module_of(summon)
  local boss_state = module and module.snapshot and module.snapshot(summon) or nil
  local pending = {}
  for _, entry in ipairs(summon.pending or {}) do
    pending[#pending + 1] = { kind = entry.kind, at = entry.at }
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
    undefended = summon.undefended,
    boss_state = boss_state,
    tracked = records.snapshot(summon),
    pending = pending,
    health_share = records.health_share(summon),
    health_bar = summon.health_bar and { status = summon.health_bar.status, resist = summon.health_bar.resist },
    spawn_note = summon.spawn_note,
    charge = summon.charge,
    lair = summon.lair,
    weaken = summon.weaken or 0,
    frequency = summon.frequency or 1,
    spawn_distance = summon.spawn_distance,
  }
end

---For tests and debugging, fixes the variant of the next Colossus beacon.
---@param variant_id string
function M.set_next_colossus(variant_id)
  for _, variant in ipairs(cfg.COLOSSUS_VARIANTS) do
    if variant.id == variant_id then
      storage.next_colossus_variant = variant_id
      return
    end
  end
  error("nexus-bosses.set_next_colossus: unknown variant " .. variant_id)
end

---Pending data contains only numbers and positions; remote.call returns a copy.
---@return table[]
function M.pending_data()
  local summon = storage.summon
  local result = {}
  for _, entry in ipairs(summon and summon.pending or {}) do
    result[#result + 1] = { kind = entry.kind, at = entry.at, data = entry.data }
  end
  return result
end

---Changes a tracked entity's health for in-game tests and debugging.
---@param unit_number integer
---@param health number
---@return boolean
function M.set_tracked_health(unit_number, health)
  local summon = storage.summon
  local record = summon and summon.by_unit[unit_number]
  if not (record and records.alive(record) and not record.hidden) then
    return false
  end
  record.entity.health = health
  return true
end

return M
