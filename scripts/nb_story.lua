-- The story of the expedition (2.4). Its camp lies near the spawn and opens with the Whisper: a broken ship, broken
-- walls, dead turrets and crash site chests, and in the ship the first log of the Long Echo (the prologue), which counts
-- as a log of the expedition. The last stand of its commander opens with Silence (or, without the gate of the warp
-- drive, when the Convergence is beaten), far beyond the lairs: an escape pod with his last log (the epilogue) and his
-- badge. Both are marked on the map for every force that reaches them.
--
--   storage.story.places  [key] = {entity, position}   key: "camp" | "last_stand"
--   storage.story.marked  [force_name] = {[key] = true}
--   storage.story.found   [force_name] = {[key] = tick}

local cfg = require("lib.nb_data")
local util = require("scripts.nb_util")
local progress = require("scripts.nb_progress")
local bearing = require("scripts.nb_bearing")

local M = {}

local SEARCH_RADIUS = 40
---@type table<string, {name: string, ring: integer[], salt: integer}>
local PLACES = {
  camp = { name = cfg.CAMP, ring = cfg.CAMP_RING, salt = 271 },
  last_stand = { name = cfg.LAST_STAND, ring = cfg.LAST_STAND_RING, salt = 997 },
}

function M.init()
  storage.story = storage.story or {}
  local s = storage.story
  s.places = s.places or {}
  s.marked = s.marked or {}
  s.found = s.found or {}
end

---@param force_name string
---@param key string
---@return boolean
function M.is_found(force_name, key)
  ---@type table<string, integer>|nil
  local found = storage.story.found[force_name]
  return found ~= nil and found[key] ~= nil
end

---@param surface LuaSurface
---@param name string
---@param position MapPosition
---@param force string|nil
---@return LuaEntity|nil
local function put(surface, name, position, force)
  if not prototypes.entity[name] then
    return nil
  end
  if not surface.can_place_entity({ name = name, position = position, force = force or "neutral" }) then
    return nil
  end
  return surface.create_entity({ name = name, position = position, force = force or "neutral" })
end

---@param surface LuaSurface
---@param name string
---@param position MapPosition
---@param items {[1]: string, [2]: integer}[]
local function chest(surface, name, position, items)
  local spot = surface.find_non_colliding_position(name, position, 6, 0.5)
  local entity = spot and put(surface, name, spot)
  if entity then
    for _, item in ipairs(items) do
      entity.insert({ name = item[1], count = item[2] })
    end
  end
end

---The camp around its ship: walls with gaps, dead turrets, chests with what the expedition left.
---@param surface LuaSurface
---@param center MapPosition
local function build_camp(surface, center)
  for step = 0, 89 do
    local angle = step / 90 * 2 * math.pi
    if math.random() < 0.7 then
      local wall = put(surface, "stone-wall", util.offset(center, angle, 15))
      if wall then
        wall.health = wall.max_health * (0.15 + math.random() * 0.6)
      end
    end
  end
  for index = 1, 3 do
    put(surface, "gun-turret-remnants", util.offset(center, index * 2.1, 11))
  end
  for _ = 1, 4 do
    put(surface, "medium-remnants", util.offset(center, math.random() * 2 * math.pi, 7 + math.random() * 5))
  end
  chest(surface, "crash-site-chest-1", util.offset(center, 1.2, 9), { { cfg.ALLOY_ITEM, 40 } })
  chest(surface, "crash-site-chest-2", util.offset(center, 4.0, 9), { { cfg.ALLOY_ITEM, 35 } })
end

---A place of the story, once: a deterministic spot of its ring.
---@param surface LuaSurface
---@param key string
---@return table|nil
local function place(surface, key)
  local existing = storage.story.places[key]
  if existing and existing.entity.valid then
    return existing
  end
  local spec = PLACES[key] --[[@as {name: string, ring: integer[], salt: integer}]]
  local seed = ((surface.map_gen_settings.seed or 0) + spec.salt * 7919) % 4294967296
  local rng = game.create_random_generator(seed --[[@as uint32]])
  local center = game.forces.player.get_spawn_position(surface)
  local wanted = util.offset(center, rng() * 2 * math.pi, rng(spec.ring[1], spec.ring[2]))
  util.ensure_generated(surface, wanted)
  local position = surface.find_non_colliding_position(spec.name, wanted, SEARCH_RADIUS, 1)
  local entity = position and surface.create_entity({ name = spec.name, position = position, force = "neutral" })
  if not entity then
    log("[nexus-bosses] no ground for the " .. key .. " of the expedition")
    return nil
  end
  entity.destructible = false
  if key == "camp" then
    entity.insert({ name = cfg.PROCESSOR_ITEM, count = 3 })
    build_camp(surface, entity.position)
  else
    entity.insert({ name = cfg.BADGE, count = 1 })
    put(surface, "big-remnants", util.offset(entity.position, 2.5, 6))
  end
  existing = { entity = entity, position = util.copy_position(entity.position) }
  storage.story.places[key] = existing
  return existing
end

---Marks a place for a force: map tag and message, once.
---@param force LuaForce
---@param surface LuaSurface
---@param key string
local function mark(force, surface, key)
  local marked = storage.story.marked[force.name] or {}
  storage.story.marked[force.name] = marked
  if marked[key] then
    return
  end
  local spot = place(surface, key)
  if not spot then
    return
  end
  marked[key] = true
  local x, y = util.xy(spot.position)
  force.chart(surface, { { x - 32, y - 32 }, { x + 32, y + 32 } })
  force.add_chart_tag(surface, { position = spot.position, icon = { type = "entity", name = (PLACES[key] --[[@as {name: string}]]).name } })
  util.say(force, { "nexus-bosses.msg-" .. key:gsub("_", "-") .. "-revealed", math.floor(x), math.floor(y), surface.name },
    util.COLORS.info)
end

---@param force LuaForce
---@return boolean
local function story_ended(force)
  local silence = force.technologies[cfg.SILENCE_TECH]
  if silence then
    return silence.researched
  end
  return progress.circle_done(force.name, #cfg.CIRCLES)
end

---The places a force has reached are marked for it.
---@param force LuaForce
function M.sync(force)
  local surface = util.nexus()
  if not surface or force.name == "enemy" or force.name == "neutral" then
    return
  end
  local whisper = force.technologies[cfg.CIRCLES[1].tech]
  if whisper and whisper.researched then
    mark(force, surface, "camp")
  end
  if story_ended(force) then
    mark(force, surface, "last_stand")
  end
end

function M.sync_all()
  for _, force in pairs(game.forces) do
    M.sync(force)
  end
end

---@param entity LuaEntity
---@return string|nil key of the place
function M.key_of(entity)
  for key, spec in pairs(PLACES) do
    if entity.name == spec.name then
      return key
    end
  end
  return nil
end

---A player opened the camp or the last stand: its log is found for the force. The container stays open for its loot.
---@param player LuaPlayer
---@param entity LuaEntity
function M.on_opened(player, entity)
  local key = M.key_of(entity)
  if not key then
    return
  end
  local force = player.force --[[@as LuaForce]]
  local found = storage.story.found[force.name] or {}
  storage.story.found[force.name] = found
  if found[key] then
    return
  end
  found[key] = game.tick
  util.say(force, { "nexus-bosses.msg-" .. key:gsub("_", "-") .. "-found" }, util.COLORS.good)
  util.play(force, "trophy")
  if key == "camp" then
    bearing.on_log_found(force)
  end
end

---@return table
function M.snapshot()
  local places = {}
  for key, spot in pairs(storage.story.places) do
    places[key] = { x = spot.position.x, y = spot.position.y, valid = spot.entity.valid }
  end
  return { places = places, marked = storage.story.marked, found = storage.story.found }
end

---For tests: finds the log of a place for a force, as opening it would.
---@param force_name string
---@param key string
function M.find(force_name, key)
  local found = storage.story.found[force_name] or {}
  storage.story.found[force_name] = found
  found[key] = game.tick
end

return M
