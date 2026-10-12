-- Helpers of the control stage. No state of their own: everything the mod remembers is in `storage`.

local cfg = require("lib.nb_data")

local M = {}

M.COLORS = {
  info = { r = 0.55, g = 0.85, b = 1 },
  warning = { r = 1, g = 0.75, b = 0.25 },
  bad = { r = 1, g = 0.4, b = 0.35 },
  good = { r = 0.5, g = 1, b = 0.5 },
}

-- the music of a fight: prototypes/nb_media.lua, lengths in seconds
---@type {name: string, seconds: integer}[]
M.FIGHT_TRACKS = { { name = "nexus-bosses-fight-urgent", seconds = 57 }, { name = "nexus-bosses-fight-pulse", seconds = 71 } }

---@param position MapPosition
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
---@return MapPosition.struct
function M.copy_position(position)
  local x, y = M.xy(position)
  return { x = x, y = y }
end

---@param center MapPosition
---@param angle number radians
---@param distance number
---@return MapPosition.struct
function M.offset(center, angle, distance)
  local x, y = M.xy(center)
  return { x = x + math.cos(angle) * distance, y = y + math.sin(angle) * distance }
end

---@param object LuaEntity|LuaPlayer
---@return LuaForce
function M.force_of(object)
  return game.forces[object.force_index]
end

---@return LuaSurface|nil
function M.nexus()
  return game.get_surface(cfg.PLANET)
end

---Connected players of the force whose character stands on the surface. Big Monsters spawns nothing without one,
---and the countdown waits for one.
---@param force LuaForce
---@param surface LuaSurface
---@return integer
function M.count_present(force, surface)
  local count = 0
  for _, player in ipairs(force.connected_players) do
    local character = player.character
    if character and character.surface_index == surface.index then
      count = count + 1
    end
  end
  return count
end

---@param receiver LuaForce|LuaPlayer
---@param message LocalisedString
---@param color Color|nil
function M.say(receiver, message, color)
  receiver.print(message, { color = color or M.COLORS.info })
end

---A sound of the mod (prototypes/nb_media.lua) for every player of the force.
---@param force LuaForce
---@param name string the sound without the prefix "nexus-bosses-"
function M.play(force, name)
  force.play_sound({ path = "nexus-bosses-" .. name })
end

---@param position MapPosition
---@return ChunkPosition.struct
function M.chunk_of(position)
  local x, y = M.xy(position)
  return { x = math.floor(x / 32), y = math.floor(y / 32) }
end

---@param surface LuaSurface
---@param position MapPosition
function M.ensure_generated(surface, position)
  if not surface.is_chunk_generated(M.chunk_of(position)) then
    surface.request_to_generate_chunks(position, 1)
    surface.force_generate_chunk_requests()
  end
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

---@param from MapPosition
---@param to MapPosition
---@return defines.direction
function M.direction_toward(from, to)
  local fx, fy = M.xy(from)
  local tx, ty = M.xy(to)
  local octant = math.floor(math.atan2(ty - fy, tx - fx) / (math.pi / 4) + 0.5) % 8
  return EIGHT_WAYS[octant]
end

-- the eight compass words of the locale, by octant of math.atan2 (y grows to the south)
local COMPASS = { "east", "southeast", "south", "southwest", "west", "northwest", "north", "northeast" }

---@param angle number radians, as in M.offset
---@return LocalisedString
function M.compass(angle)
  local octant = math.floor(angle / (math.pi / 4) + 0.5) % 8
  return { "nexus-bosses.compass-" .. COMPASS[octant + 1] }
end

-- a spot is first looked for clear of the player's buildings by 40 tiles, then 20, then 8
local AVOID_RADII = { 40, 20, 8 }
local TRIES = 24

---A free position for an entity between min_radius and max_radius from the center, near the given angle (the
---search widens to the whole ring), as far as it can be from the buildings of avoid_force. Without free ground in the
---ring it comes closer: second result "closer".
---@param surface LuaSurface
---@param center MapPosition
---@param angle number preferred direction, radians
---@param name string entity prototype (its collision box decides where it fits)
---@param min_radius number
---@param max_radius number
---@param avoid_force string
---@return MapPosition|nil
---@return string|nil note nil, or "closer"
function M.find_spawn_position(surface, center, angle, name, min_radius, max_radius, avoid_force)
  local best, best_level
  for try = 1, TRIES do
    local spread = math.min(1, try / TRIES * 2) * math.pi -- a cone that opens up to the whole ring
    local candidate = M.offset(center, angle + (math.random() * 2 - 1) * spread,
      min_radius + math.random() * (max_radius - min_radius))
    M.ensure_generated(surface, candidate)
    local position = surface.find_non_colliding_position(name, candidate, 12, 1)
    if position then
      local actual = M.distance(position, center)
      if actual >= min_radius and actual <= max_radius then
        local level = #AVOID_RADII + 1
        for index, radius in ipairs(AVOID_RADII) do
          if surface.count_entities_filtered({ position = position, radius = radius, force = avoid_force, limit = 1 }) == 0 then
            level = index
            break
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
    return best, nil
  end
  for _, distance in ipairs({ min_radius * 0.6, min_radius * 0.3 }) do
    local candidate = M.offset(center, angle, distance)
    M.ensure_generated(surface, candidate)
    local position = surface.find_non_colliding_position(name, candidate, 32, 1)
    if position then
      return position, "closer"
    end
  end
  return nil, nil
end

return M
