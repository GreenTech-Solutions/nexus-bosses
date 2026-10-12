-- Bearings (2.3). Every boss has a lair on Nexus, on a ring around the spawn of the player force farther out than the
-- wrecks (cfg.LAIR_RINGS), placed the first time a direction finder looks for it. A direction finder (a radar) is set
-- to a boss in a panel next to its window; after every sector it scans it draws a bearing toward the lair, off by a
-- random angle that narrows with every scan. Two precise bearings of a force on the same boss that cross at a wide
-- enough angle find the lair: it is marked on the map and the remains of the boss appear there. A beacon lit within
-- cfg.LAIR_RADIUS of the lair of its boss gives, at the victory, a second trophy of a better quality (one step better
-- with every fight in that lair) and loot worth a share of the beacon.
--
--   storage.bearing.lairs     [boss_id] = position
--   storage.bearing.remains   [boss_id] = true once the remains stand
--   storage.bearing.found     [force_name] = {[boss_id] = tick}
--   storage.bearing.wins      [force_name] = {[boss_id] = fights won in the lair}
--   storage.bearing.finders   [unit_number] = {entity, boss, scans, lines}
--   storage.bearing.pylons    [boss_id] = the pylon of suppression of the lair (2.4); pylon_units [unit_number] = boss_id
--   storage.bearing.pylon_quality [force_name] = {[boss_id] = quality of the trophy that repaired it}
--   storage.bearing.pylon_fx  [force_name] = {[boss_id] = {render objects of the repaired look}}

local cfg = require("lib.nb_data")
local util = require("scripts.nb_util")
local progress = require("scripts.nb_progress")

local M = {}

local PANEL = "nexus_bosses_finder"
local CHOOSER = "nexus_bosses_finder_boss"
local SPREAD_START = 30 -- degrees, either side
local SPREAD_DECAY = 0.75 -- per scan
local PRECISE = 2 -- degrees: a bearing this narrow counts for a crossing
local MIN_CROSSING = 15 -- degrees between two bearings that find a lair
local LINE_LENGTH = 1200
local SEARCH_RADIUS = 40
-- the colours of the stages, as the beacon antennas
local COLORS = { { r = 0.55, g = 0.85, b = 1 }, { r = 1, g = 0.8, b = 0.35 }, { r = 1, g = 0.4, b = 0.35 } }

function M.init()
  storage.bearing = storage.bearing or {}
  local b = storage.bearing
  b.lairs = b.lairs or {}
  b.remains = b.remains or {}
  b.found = b.found or {}
  b.wins = b.wins or {}
  b.finders = b.finders or {}
  b.pylons = b.pylons or {}
  b.pylon_units = b.pylon_units or {}
  b.pylon_quality = b.pylon_quality or {}
  b.pylon_fx = b.pylon_fx or {}
  -- lairs found before 2.4 get their pylons
  local surface = util.nexus()
  if surface then
    for boss_id in pairs(b.remains) do
      M.raise_pylon(surface, boss_id)
    end
  end
end

---@param scans integer
---@return number degrees either side
local function spread_of(scans)
  return SPREAD_START * SPREAD_DECAY ^ scans
end

---@param force_name string
---@param boss_id string
---@return boolean
function M.is_found(force_name, boss_id)
  ---@type table<string, integer>|nil
  local found = storage.bearing.found[force_name]
  return found ~= nil and found[boss_id] ~= nil
end

---@param force_name string
---@param boss_id string
---@return integer
function M.wins_of(force_name, boss_id)
  local wins = storage.bearing.wins[force_name]
  return wins and wins[boss_id] or 0
end

---The quality of the second trophy of the next fight in the lair.
---@param force_name string
---@param boss_id string
---@return string
function M.next_quality(force_name, boss_id)
  local step = math.min(M.wins_of(force_name, boss_id) + 1, #cfg.LAIR_QUALITIES)
  return cfg.LAIR_QUALITIES[step] --[[@as string]]
end

---@param boss_id string
---@return MapPosition.struct|nil
function M.lair_position(boss_id)
  return storage.bearing.lairs[boss_id]
end

---The lair of a boss: a deterministic spot of its ring (the map seed and the boss), open ground near it.
---@param surface LuaSurface
---@param boss_id string
---@return MapPosition.struct
local function place_lair(surface, boss_id)
  local lair = storage.bearing.lairs[boss_id]
  if lair then
    return lair
  end
  local boss = cfg.BOSSES[boss_id]
  local ring = cfg.LAIR_RINGS[boss.circle] --[[@as integer[] ]]
  local seed = ((surface.map_gen_settings.seed or 0) + 31337 + boss.circle * 7919 + boss.slot * 104729) % 4294967296
  local rng = game.create_random_generator(seed --[[@as uint32]])
  local center = game.forces.player.get_spawn_position(surface)
  local wanted = util.offset(center, rng() * 2 * math.pi, rng(ring[1], ring[2]))
  util.ensure_generated(surface, wanted)
  local position = surface.find_non_colliding_position("rocket-silo", wanted, SEARCH_RADIUS, 2) or wanted
  lair = util.copy_position(position)
  storage.bearing.lairs[boss_id] = lair
  return lair
end

---The remains of the boss and scorched ground, once, the first time any force finds the lair.
---@param surface LuaSurface
---@param boss_id string
local function raise_remains(surface, boss_id)
  if storage.bearing.remains[boss_id] then
    return
  end
  storage.bearing.remains[boss_id] = true
  local lair = storage.bearing.lairs[boss_id] --[[@as MapPosition.struct]]
  surface.create_entity({ name = cfg.LAIR_REMAINS_PREFIX .. boss_id, position = lair })
  -- creep and scorched ground: Nexus has no nests, so the creep marks the lair
  local decoratives = {}
  for _, entry in ipairs({ { "enemy-decal", 30 }, { "enemy-decal-transparent", 20 }, { "crater-large", 4 } }) do
    if prototypes.decorative[entry[1]] then
      for _ = 1, entry[2] do
        decoratives[#decoratives + 1] = {
          name = entry[1],
          position = util.offset(lair, math.random() * 2 * math.pi, math.random() * cfg.LAIR_RADIUS * 0.7),
          amount = 1,
        }
      end
    end
  end
  surface.create_decoratives({ decoratives = decoratives, check_collision = false })
  M.raise_pylon(surface, boss_id)
  if prototypes.entity[cfg.LAIR_SCORCH] then
    for _ = 1, 5 do
      surface.create_entity({ name = cfg.LAIR_SCORCH, position = util.offset(lair, math.random() * 2 * math.pi, 3 + math.random() * 12) })
    end
  end
end

---@param finder table
local function clear_lines(finder)
  for _, line in ipairs(finder.lines or {}) do
    if line.valid then
      line.destroy()
    end
  end
  finder.lines = {}
end

---@param force LuaForce
---@param surface LuaSurface
---@param boss_id string
local function reveal_lair(force, surface, boss_id)
  local found = storage.bearing.found[force.name] or {}
  storage.bearing.found[force.name] = found
  found[boss_id] = game.tick
  for _, finder in pairs(storage.bearing.finders) do
    if finder.boss == boss_id and finder.entity.valid and finder.entity.force_index == force.index then
      clear_lines(finder)
    end
  end
  local lair = storage.bearing.lairs[boss_id] --[[@as MapPosition.struct]]
  local x, y = util.xy(lair)
  force.chart(surface, { { x - 48, y - 48 }, { x + 48, y + 48 } })
  raise_remains(surface, boss_id)
  force.add_chart_tag(surface, { position = lair, icon = { type = "entity", name = cfg.BOSSES[boss_id].entity } })
  util.say(force, { "nexus-bosses.msg-lair-found", { "nexus-bosses.boss-" .. boss_id }, math.floor(x), math.floor(y),
    surface.name }, util.COLORS.good)
  util.play(force, "trophy")
end

---@param from MapPosition
---@param to MapPosition
---@return number radians
local function angle_to(from, to)
  local fx, fy = util.xy(from)
  local tx, ty = util.xy(to)
  return math.atan2(ty - fy, tx - fx)
end

---Two precise bearings of the force on the boss, wide enough apart, find its lair.
---@param force LuaForce
---@param surface LuaSurface
---@param boss_id string
local function check_crossing(force, surface, boss_id)
  if M.is_found(force.name, boss_id) then
    return
  end
  local lair = storage.bearing.lairs[boss_id] --[[@as MapPosition.struct]]
  local angles, precise = {}, {}
  for _, finder in pairs(storage.bearing.finders) do
    local entity = finder.entity
    if entity.valid and finder.boss == boss_id and entity.force_index == force.index and spread_of(finder.scans) <= PRECISE then
      angles[#angles + 1] = angle_to(entity.position, lair)
      precise[#precise + 1] = finder
    end
  end
  for i = 1, #angles do
    for j = i + 1, #angles do
      local difference = math.abs(angles[i] - angles[j]) % (2 * math.pi)
      difference = math.deg(math.min(difference, 2 * math.pi - difference))
      -- two bearings toward the same point cross well between 15 and 165 degrees
      if difference >= MIN_CROSSING and difference <= 180 - MIN_CROSSING then
        reveal_lair(force, surface, boss_id)
        return
      end
    end
  end
  -- precise bearings that run almost side by side cross nowhere: the finders have to stand farther apart
  if #precise >= 2 then
    local told = false
    for _, finder in ipairs(precise) do
      told = told or finder.parallel == true
      finder.parallel = true
    end
    if not told then
      util.say(force, { "nexus-bosses.msg-bearings-parallel", { "nexus-bosses.boss-" .. boss_id } }, util.COLORS.warning)
    end
  end
end

---@param entity LuaEntity
function M.on_built(entity)
  storage.bearing.finders[entity.unit_number] = { entity = entity, boss = nil, scans = 0, lines = {} }
  script.register_on_object_destroyed(entity)
end

---@param unit_number integer
function M.on_destroyed(unit_number)
  local finder = storage.bearing.finders[unit_number]
  if finder then
    clear_lines(finder)
    storage.bearing.finders[unit_number] = nil
  end
end

---A finder scanned a sector: a new bearing, narrower than the last.
---@param radar LuaEntity
function M.on_sector_scanned(radar)
  local finder = storage.bearing.finders[radar.unit_number]
  if not (finder and finder.boss) then
    return
  end
  local surface = radar.surface
  if surface.name ~= cfg.PLANET then
    return
  end
  local boss_id = finder.boss --[[@as string]]
  local force = util.force_of(radar)
  if M.is_found(force.name, boss_id) then
    clear_lines(finder) -- the lair is on the map: the bearings have done their job
    M.refresh_panels(radar)
    return
  end
  local lair = place_lair(surface, boss_id)
  finder.scans = finder.scans + 1
  local spread = math.rad(spread_of(finder.scans))
  local angle = angle_to(radar.position, lair) + (math.random() * 2 - 1) * spread
  local color = COLORS[cfg.BOSSES[boss_id].circle] --[[@as Color]]
  clear_lines(finder)
  local to = util.offset(radar.position, angle, LINE_LENGTH)
  for _, mode in ipairs({ "game", "chart" }) do
    finder.lines[#finder.lines + 1] = rendering.draw_line({
      color = color,
      width = mode == "game" and 3 or 2,
      from = radar,
      to = to,
      surface = surface,
      forces = { force },
      render_mode = mode,
      dash_length = 4,
      gap_length = 2,
    })
  end
  check_crossing(force, surface, boss_id)
  M.refresh_panels(radar)
end

---Points a finder at a boss; its bearings start over.
---@param entity LuaEntity
---@param boss_id string|nil
function M.choose(entity, boss_id)
  local finder = storage.bearing.finders[entity.unit_number]
  if not finder then
    M.on_built(entity)
    finder = storage.bearing.finders[entity.unit_number]
  end
  if finder.boss == boss_id then
    return
  end
  finder.boss = boss_id
  finder.scans = 0
  finder.parallel = nil
  clear_lines(finder)
end

-- Panel next to the radar window -----------------------------------------------------------------------------------

---Bosses of the stages the force has opened.
---@param force LuaForce
---@return string[]
local function open_bosses(force)
  local list = {}
  for _, circle in ipairs(cfg.CIRCLES) do
    local technology = force.technologies[circle.tech]
    if technology and technology.researched then
      for _, id in ipairs(circle.bosses) do
        list[#list + 1] = id
      end
    end
  end
  return list
end

---@param finder table
---@param force_name string
---@return LocalisedString
local function status_of(finder, force_name)
  if not finder.boss then
    return { "nexus-bosses.finder-idle" }
  elseif M.is_found(force_name, finder.boss) then
    return { "nexus-bosses.finder-found" }
  elseif finder.scans == 0 then
    return { "nexus-bosses.finder-waiting" }
  end
  local spread = spread_of(finder.scans)
  if finder.parallel then
    return { "nexus-bosses.finder-parallel", string.format("%.1f", spread) }
  end
  return { spread <= PRECISE and "nexus-bosses.finder-precise" or "nexus-bosses.finder-scanning",
    string.format("%.1f", spread), finder.scans }
end

---@param player LuaPlayer
---@param entity LuaEntity
function M.open_panel(player, entity)
  local old = player.gui.relative[PANEL]
  if old then
    old.destroy()
  end
  if not storage.bearing.finders[entity.unit_number] then
    M.on_built(entity)
  end
  local finder = storage.bearing.finders[entity.unit_number] --[[@as table]]
  local force = player.force --[[@as LuaForce]]
  local frame = player.gui.relative.add({ ---@diagnostic disable-line: param-type-mismatch
    type = "frame",
    name = PANEL,
    caption = { "nexus-bosses.finder-title" },
    direction = "vertical",
    anchor = { gui = defines.relative_gui_type.radar_gui, position = defines.relative_gui_position.right, names = { cfg.FINDER } },
    tags = { unit = entity.unit_number },
  })
  local inner = frame.add({ type = "frame", style = "inside_shallow_frame_with_padding", direction = "vertical" })
  local bosses = open_bosses(force)
  local items = { { "nexus-bosses.finder-none" } }
  local selected = 1
  for index, id in ipairs(bosses) do
    items[#items + 1] = { "nexus-bosses.boss-" .. id }
    if finder.boss == id then
      selected = index + 1
    end
  end
  inner.add({ type = "label", caption = { "nexus-bosses.finder-target" }, style = "caption_label" })
  local chooser = inner.add({ type = "drop-down", name = CHOOSER, items = items, selected_index = selected,
    tags = { bosses = bosses } })
  chooser.style.minimal_width = 220
  local status = inner.add({ type = "label", name = "status", caption = status_of(finder, force.name) })
  status.style.single_line = false
  status.style.maximal_width = 240
  local hint = inner.add({ type = "label", caption = { "nexus-bosses.finder-hint" } })
  hint.style.single_line = false
  hint.style.maximal_width = 240
  hint.style.font_color = { r = 0.7, g = 0.7, b = 0.7 }
end

---The status lines of open panels of this finder.
---@param entity LuaEntity
function M.refresh_panels(entity)
  local finder = storage.bearing.finders[entity.unit_number]
  if not finder then
    return
  end
  for _, player in pairs(game.connected_players) do
    local frame = player.gui.relative[PANEL]
    if frame and frame.tags.unit == entity.unit_number then
      frame.children[1].status.caption = status_of(finder, player.force.name --[[@as string]])
    end
  end
end

---@param event EventData.on_gui_selection_state_changed
function M.on_selection_changed(event)
  local element = event.element
  if not (element.valid and element.name == CHOOSER) then
    return
  end
  local player = game.get_player(event.player_index) --[[@as LuaPlayer]]
  local entity = player.opened
  if not (entity and entity.object_name == "LuaEntity" and entity.name == cfg.FINDER) then
    return
  end
  ---@cast entity LuaEntity
  local bosses = element.tags.bosses --[[@as string[] ]]
  M.choose(entity, element.selected_index > 1 and bosses[element.selected_index - 1] or nil)
  M.refresh_panels(entity)
end

-- Lair fights ----------------------------------------------------------------------------------------------------

---@param force_name string
---@param boss_id string
---@param position MapPosition
---@return boolean the beacon stands in the found lair of its boss
function M.in_lair(force_name, boss_id, position)
  local lair = storage.bearing.lairs[boss_id] --[[@as MapPosition.struct|nil]]
  return lair ~= nil and M.is_found(force_name, boss_id) and util.distance(lair, position) <= cfg.LAIR_RADIUS
end

---A victory in the lair: the second trophy, one quality step better than the last, and loot.
---@param force LuaForce
---@param surface LuaSurface
---@param boss_id string
---@param position MapPosition
function M.lair_victory(force, surface, boss_id, position)
  local quality = M.next_quality(force.name, boss_id)
  local wins = storage.bearing.wins[force.name] or {}
  storage.bearing.wins[force.name] = wins
  wins[boss_id] = (wins[boss_id] or 0) + 1
  progress.drop_trophy(force, surface, boss_id, position, quality)
  local circle = cfg.CIRCLES[cfg.BOSSES[boss_id].circle]
  local cost = settings.startup["nexus-bosses-beacon-cost"].value --[[@as number]]
  for _, loot in ipairs({ { cfg.ALLOY_ITEM, circle.alloy }, { cfg.PROCESSOR_ITEM, circle.processors } }) do
    local count = math.max(1, math.floor(loot[2] * cost * cfg.LAIR_LOOT_SHARE + 0.5))
    surface.spill_item_stack({ position = position, stack = { name = loot[1], count = count }, enable_looted = true,
      allow_belts = false })
  end
  util.say(force, { "nexus-bosses.msg-lair-loot", { "nexus-bosses.boss-" .. boss_id } }, util.COLORS.good)
end

-- Pylons of suppression (2.4) ---------------------------------------------------------------------------------------

---The broken pylon of a lair, once.
---@param surface LuaSurface
---@param boss_id string
function M.raise_pylon(surface, boss_id)
  local old = storage.bearing.pylons[boss_id]
  local lair = storage.bearing.lairs[boss_id]
  if (old and old.valid) or not lair then
    return
  end
  local position = surface.find_non_colliding_position(cfg.PYLON, util.offset(lair, math.pi / 4, 8), 16, 0.5)
  local pylon = position and surface.create_entity({ name = cfg.PYLON, position = position, force = "neutral" })
  if not pylon then
    return
  end
  pylon.destructible = false
  pylon.minable_flag = false
  storage.bearing.pylons[boss_id] = pylon
  storage.bearing.pylon_units[pylon.unit_number] = boss_id
end

---@param force_name string
---@param boss_id string
---@return string|nil quality of the trophy in the pylon
function M.pylon_quality(force_name, boss_id)
  local qualities = storage.bearing.pylon_quality[force_name]
  return qualities and qualities[boss_id]
end

---The share of health a boss called at a position loses to the pylon of its lair.
---@param force_name string
---@param boss_id string
---@param position MapPosition
---@return number 0..1
function M.pylon_share(force_name, boss_id, position)
  local quality = M.pylon_quality(force_name, boss_id)
  if not (quality and M.in_lair(force_name, boss_id, position)) then
    return 0
  end
  return cfg.PYLON_SHARES[quality] or 0
end

-- the colours of the qualities, for the glow of a repaired pylon
local QUALITY_COLORS = {
  uncommon = { r = 0.35, g = 0.9, b = 0.45 },
  rare = { r = 0.35, g = 0.6, b = 1 },
  epic = { r = 0.75, g = 0.4, b = 1 },
  legendary = { r = 1, g = 0.6, b = 0.25 },
}

---The repaired look for the force that repaired it: the summon circle and a glow in the colour of the quality.
---@param force LuaForce
---@param boss_id string
local function draw_pylon(force, boss_id)
  local pylon = storage.bearing.pylons[boss_id]
  local quality = M.pylon_quality(force.name, boss_id)
  if not (pylon and pylon.valid and quality) then
    return
  end
  local all = storage.bearing.pylon_fx[force.name] or {}
  storage.bearing.pylon_fx[force.name] = all
  for _, object in ipairs(all[boss_id] or {}) do
    if object.valid then
      object.destroy()
    end
  end
  local color = QUALITY_COLORS[quality] or { r = 1, g = 1, b = 1 }
  all[boss_id] = {
    rendering.draw_animation({ animation = "nexus-bosses-summon-circle", target = pylon, surface = pylon.surface,
      tint = color, render_layer = "lower-object", forces = { force }, x_scale = 2.4, y_scale = 2.4 }),
    rendering.draw_light({ sprite = "utility/light_medium", target = pylon, surface = pylon.surface, scale = 7,
      intensity = 1, color = color, forces = { force } }),
  }
end

---The pylon of a lair is repaired for a force with a trophy of this quality.
---@param force LuaForce
---@param boss_id string
---@param quality string
function M.repair_pylon(force, boss_id, quality)
  local qualities = storage.bearing.pylon_quality[force.name] or {}
  storage.bearing.pylon_quality[force.name] = qualities
  qualities[boss_id] = quality
  draw_pylon(force, boss_id)
  util.say(force, { "nexus-bosses.msg-pylon-repaired", { "nexus-bosses.boss-" .. boss_id },
    math.floor((cfg.PYLON_SHARES[quality] or 0) * 100) }, util.COLORS.good)
  util.play(force, "stage-complete")
end

---A player closed the pylon: a trophy of its boss of a better quality repairs it; anything else goes back.
---@param player LuaPlayer
---@param pylon LuaEntity
function M.on_pylon_closed(player, pylon)
  local boss_id = storage.bearing.pylon_units[pylon.unit_number]
  local inventory = pylon.get_inventory(defines.inventory.chest)
  if not (boss_id and inventory) then
    return
  end
  local force = player.force --[[@as LuaForce]]
  local trophy = cfg.trophy_name(boss_id)
  local current = M.pylon_quality(force.name, boss_id)
  local current_level = current and prototypes.quality[current].level or 0
  local repaired
  for _, item in ipairs(inventory.get_contents()) do
    local quality = item.quality --[[@as string]]
    local level = prototypes.quality[quality].level
    if item.name == trophy and cfg.PYLON_SHARES[quality] and level > current_level and not repaired then
      inventory.remove({ name = item.name, quality = quality, count = 1 })
      repaired = quality
    end
  end
  -- whatever is left goes back to the player
  for _, item in ipairs(inventory.get_contents()) do
    local stack = { name = item.name, quality = item.quality, count = item.count }
    local given = player.insert(stack)
    if given < item.count then
      pylon.surface.spill_item_stack({ position = player.position, stack = { name = item.name, quality = item.quality,
        count = item.count - given }, enable_looted = true, allow_belts = false })
    end
  end
  inventory.clear()
  if repaired then
    M.repair_pylon(force, boss_id, repaired)
  elseif not current then
    util.say(player, { "nexus-bosses.msg-pylon-needs", string.format("[item=%s,quality=uncommon]", trophy) }, util.COLORS.info)
  end
end

---@param unit_number integer
---@return boolean the entity is a pylon of a lair
function M.is_pylon(unit_number)
  return storage.bearing.pylon_units[unit_number] ~= nil
end

-- Technology -------------------------------------------------------------------------------------------------------

---The first log of the expedition teaches the bearings.
---@param force LuaForce
function M.on_log_found(force)
  if progress.research(force, cfg.BEARING_TECH) then
    util.say(force, { "nexus-bosses.msg-bearing-learned" }, util.COLORS.good)
  end
end

---For tests: finds the lair of a boss for a force, as two crossing bearings would.
---@param force_name string
---@param boss_id string
---@return MapPosition.struct|nil
function M.find_lair(force_name, boss_id)
  local surface = util.nexus()
  local force = game.forces[force_name]
  if not (surface and force and cfg.BOSSES[boss_id]) then
    return nil
  end
  place_lair(surface, boss_id)
  reveal_lair(force, surface, boss_id)
  return storage.bearing.lairs[boss_id]
end

---@return table
function M.snapshot()
  local finders = {}
  for unit, finder in pairs(storage.bearing.finders) do
    finders[unit] = { boss = finder.boss, scans = finder.scans, valid = finder.entity.valid }
  end
  local pylons = {}
  for boss_id, pylon in pairs(storage.bearing.pylons) do
    pylons[boss_id] = pylon.valid and { x = pylon.position.x, y = pylon.position.y, unit = pylon.unit_number } or false
  end
  return { lairs = storage.bearing.lairs, found = storage.bearing.found, wins = storage.bearing.wins, finders = finders,
    pylons = pylons, pylon_quality = storage.bearing.pylon_quality }
end

return M
