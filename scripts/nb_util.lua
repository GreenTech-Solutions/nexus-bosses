-- Helpers of the control stage. No state of its own: everything the mod remembers is in `storage`.

local cfg = require("lib.nb_data")

local M = {}

M.COLORS = {
  info = { r = 0.55, g = 0.85, b = 1 },
  warning = { r = 1, g = 0.75, b = 0.25 },
  bad = { r = 1, g = 0.4, b = 0.35 },
  good = { r = 0.5, g = 1, b = 0.5 },
}

-- Sounds: the first one that exists is played. The alarms of mferrari_lib come with Big-Monsters.
M.SOUND_ALARM = { "mf_sound_alarm_1", "utility/alert_destroyed" }
M.SOUND_SIREN = { "mf_sound_siren", "utility/game_lost" }
M.SOUND_VICTORY = { "utility/research_completed" }

---The length of the countdown of a summon in seconds (map setting).
---@return integer
function M.countdown_seconds()
  return settings.global["nexus-bosses-countdown"].value --[[@as integer]]
end

---The two coordinates of a position. The API always returns positions with the keys x and y; the type of
---MapPosition also allows the array form, which is why the scripts read coordinates through this function.
---@param position MapPosition|ChunkPosition
---@return number x
---@return number y
function M.xy(position)
  ---@cast position MapPosition.struct
  return position.x, position.y
end

---@param a MapPosition
---@param b MapPosition
---@return number
function M.distance(a, b)
  local ax, ay = M.xy(a)
  local bx, by = M.xy(b)
  return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2)
end

---@param position MapPosition
---@return MapPosition.struct a plain copy that is safe to keep in storage
function M.copy_position(position)
  local x, y = M.xy(position)
  return { x = x, y = y }
end

---The force of an entity or a player as an object (the type of the attribute `force` is the union ForceID).
---@param object LuaEntity|LuaPlayer
---@return LuaForce
function M.force_of(object)
  return game.forces[object.force_index]
end

---The Nexus surface, or nil before it exists.
---@return LuaSurface|nil
function M.nexus()
  local surface = game.get_surface(cfg.PLANET)
  if surface and surface.valid then
    return surface
  end
  return nil
end

---Number of connected players of the force whose character stands on the surface. Big-Monsters spawns nothing
---without such a player, and the countdown of a summon waits for one.
---@param force LuaForce
---@param surface LuaSurface
---@return integer
function M.count_present(force, surface)
  local count = 0
  for _, player in ipairs(force.connected_players) do
    local character = player.character
    if character and character.valid and character.surface_index == surface.index then
      count = count + 1
    end
  end
  return count
end

---Prints to a force (or a single player), skipping invalid receivers.
---@param receiver LuaForce|LuaPlayer|nil
---@param message LocalisedString
---@param color Color|nil
function M.say(receiver, message, color)
  if receiver and receiver.valid then
    receiver.print(message, { color = color or M.COLORS.info })
  end
end

---Plays the first valid sound of the list to the whole force.
---@param force LuaForce
---@param candidates string[]
function M.play(force, candidates)
  if not (force and force.valid) then
    return
  end
  for _, path in ipairs(candidates) do
    if helpers.is_valid_sound_path(path) then
      force.play_sound({ path = path })
      return
    end
  end
end

---@param position MapPosition
---@return ChunkPosition.struct
function M.chunk_of(position)
  local x, y = M.xy(position)
  return { x = math.floor(x / 32), y = math.floor(y / 32) }
end

---Makes sure the chunk around the position exists (bosses and their guards need ground to stand on).
---@param surface LuaSurface
---@param position MapPosition
function M.ensure_generated(surface, position)
  if surface.is_chunk_generated(M.chunk_of(position)) then
    return
  end
  surface.request_to_generate_chunks(position, 1)
  surface.force_generate_chunk_requests()
end

---@type table<integer, defines.direction>
local EIGHT_WAYS = {
  [0] = defines.direction.east,
  [1] = defines.direction.southeast,
  [2] = defines.direction.south,
  [3] = defines.direction.southwest,
  [4] = defines.direction.west,
  [5] = defines.direction.northwest,
  [6] = defines.direction.north,
  [7] = defines.direction.northeast,
}

---The 8-way direction from one position towards another.
---@param from MapPosition
---@param to MapPosition
---@return defines.direction
function M.direction_toward(from, to)
  local fx, fy = M.xy(from)
  local tx, ty = M.xy(to)
  local dx = tx - fx
  local dy = ty - fy
  if dx == 0 and dy == 0 then
    return defines.direction.north
  end
  local octant = math.floor(math.atan2(dy, dx) / (math.pi / 4) + 0.5) % 8
  return EIGHT_WAYS[octant] or defines.direction.north
end

-- Player buildings closer than these to a candidate spawn position make it worse than a free one: the candidates are
-- tried clear of buildings by 40 tiles first, then 20, then 8.
local AVOID_RADII = { 40, 20, 8 }
-- random candidates in the ring; the rest of the ring is what the search around a candidate may move it by
local RING_TRIES = 24
local RING_MARGIN = 12

---A free position for an entity 150-250 tiles (by default) from the center: random direction, ground that
---exists (it is generated on demand), as far as possible from the buildings of the player force. The distance is kept:
---when every candidate of the ring is near buildings the least crowded one is taken (note "crowded"), and only when the
---ring has no free ground at all the search moves to closer rings (note "closer") and, as the last resort, to the
---neighbourhood of the center (note "closest"). The note is the second result so that the caller can log it.
---@param surface LuaSurface
---@param center MapPosition
---@param name string entity prototype (its collision box decides where it fits)
---@param min_radius number
---@param max_radius number
---@param avoid_force string|nil force whose buildings the position should stay clear of
---@return MapPosition|nil
---@return string|nil note "crowded", "closer", "closest" or nil for a position in the ring clear of buildings
function M.find_spawn_position(surface, center, name, min_radius, max_radius, avoid_force)
  local cx, cy = M.xy(center)
  local middle = (min_radius + max_radius) / 2
  local inner = math.min(min_radius + RING_MARGIN, middle)
  local outer = math.max(max_radius - RING_MARGIN, middle)
  local best, best_level
  for _ = 1, RING_TRIES do
    local angle = math.random() * 2 * math.pi
    local distance = inner + math.random() * (outer - inner)
    local candidate = { x = cx + math.cos(angle) * distance, y = cy + math.sin(angle) * distance }
    M.ensure_generated(surface, candidate)
    local position = surface.find_non_colliding_position(name, candidate, RING_MARGIN, 1)
    if position then
      local actual = M.distance(position, center)
      if actual >= min_radius and actual <= max_radius then
        -- level 1: clear of buildings by the widest radius, ..., level 4: buildings within the narrowest one
        local level = #AVOID_RADII + 1
        if not avoid_force then
          level = 1
        else
          for index, radius in ipairs(AVOID_RADII) do
            if surface.count_entities_filtered({ position = position, radius = radius, force = avoid_force, limit = 1 }) == 0 then
              level = index
              break
            end
          end
        end
        if level == 1 then
          return position, nil
        end
        if not best_level or level < best_level then
          best, best_level = position, level
        end
      end
    end
  end
  if best then
    return best, "crowded"
  end
  -- no ground in the ring: better a boss nearer than none
  for _, distance in ipairs({ 120, 90, 60, 40 }) do
    local angle = math.random() * 2 * math.pi
    local candidate = { x = cx + math.cos(angle) * distance, y = cy + math.sin(angle) * distance }
    M.ensure_generated(surface, candidate)
    local position = surface.find_non_colliding_position(name, candidate, 32, 1)
    if position then
      return position, "closer"
    end
  end
  return surface.find_non_colliding_position(name, center, 64, 1), "closest"
end

return M
