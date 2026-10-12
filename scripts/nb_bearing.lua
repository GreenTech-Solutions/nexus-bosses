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
  if prototypes.entity[cfg.LAIR_SCORCH] then
    for _ = 1, 5 do
      surface.create_entity({ name = cfg.LAIR_SCORCH, position = util.offset(lair, math.random() * 2 * math.pi, 3 + math.random() * 12) })
    end
  end
end

---@param force LuaForce
---@param surface LuaSurface
---@param boss_id string
local function reveal_lair(force, surface, boss_id)
  local found = storage.bearing.found[force.name] or {}
  storage.bearing.found[force.name] = found
  found[boss_id] = game.tick
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
  local angles = {}
  for _, finder in pairs(storage.bearing.finders) do
    local entity = finder.entity
    if entity.valid and finder.boss == boss_id and entity.force_index == force.index and spread_of(finder.scans) <= PRECISE then
      angles[#angles + 1] = angle_to(entity.position, lair)
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
  local lair = place_lair(surface, boss_id)
  finder.scans = finder.scans + 1
  local spread = math.rad(spread_of(finder.scans))
  local angle = angle_to(radar.position, lair) + (math.random() * 2 - 1) * spread
  local force = util.force_of(radar)
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
  return { lairs = storage.bearing.lairs, found = storage.bearing.found, wins = storage.bearing.wins, finders = finders }
end

return M
