-- Storms wake the ruins (2.3). While a storm of Nexus-Threat rages, every WAKE_SECONDS the mod strikes a lightning
-- attractor ruin of Nexus (fulgoran-ruin-attractor) near a player with lightning and wakes it: it glows, calls
-- lightning down around itself and drops one charged shard, until the storm ends. A ruin wakes once a storm. Only
-- ruins in charted land within reach of a player on Nexus wake, so a woken ruin is one someone can get to.
--
--   storage.storms.ruins   [unit_number] = ruin entity (every attractor ruin of Nexus)
--   storage.storms.awake   [unit_number] = {entity, light, tags, next_strike}
--   storage.storms.woken   [unit_number] = true: woke in this storm
--   storage.storms.raging  the storm was on at the last check
--   storage.storms.next_wake  tick

local cfg = require("lib.nb_data")
local util = require("scripts.nb_util")

local M = {}

local WAKE_SECONDS = 30
local MAX_AWAKE = 3
local STRIKE_SECONDS = 4
local STRIKE_RADIUS = 10
local REACH = 300 -- tiles from a player character on Nexus
local GLOW = { r = 0.55, g = 0.8, b = 1 }

function M.init()
  storage.storms = storage.storms or {}
  local s = storage.storms
  s.ruins = s.ruins or {}
  s.awake = s.awake or {}
  s.woken = s.woken or {}
  s.next_wake = s.next_wake or 0
  if not s.scanned then
    local surface = util.nexus()
    if surface then
      s.scanned = true
      for _, ruin in ipairs(surface.find_entities_filtered({ name = cfg.RUIN_ATTRACTOR })) do
        s.ruins[ruin.unit_number] = ruin
      end
    end
  end
end

---@param event EventData.on_chunk_generated
function M.on_chunk_generated(event)
  if event.surface.name ~= cfg.PLANET then
    return
  end
  storage.storms.scanned = true
  for _, ruin in ipairs(event.surface.find_entities_filtered({ name = cfg.RUIN_ATTRACTOR, area = event.area })) do
    storage.storms.ruins[ruin.unit_number] = ruin
  end
end

---@param surface LuaSurface
---@param position MapPosition
local function strike(surface, position)
  -- Nexus has no lightning generator (execute_lightning fails there): the entity, as Nexus-Threat makes it
  surface.create_entity({ name = "lightning", position = position })
end

---Players with a character on Nexus.
---@param surface LuaSurface
---@return LuaPlayer[]
local function players_on(surface)
  local list = {}
  for _, player in pairs(game.connected_players) do
    local character = player.character
    if character and character.surface_index == surface.index then
      list[#list + 1] = player
    end
  end
  return list
end

---@param surface LuaSurface
---@return LuaEntity|nil
local function pick_ruin(surface)
  local players = players_on(surface)
  if #players == 0 then
    return nil
  end
  local candidates = {}
  for unit, ruin in pairs(storage.storms.ruins) do
    if not ruin.valid then
      storage.storms.ruins[unit] = nil
    elseif not storage.storms.woken[unit] then
      for _, player in ipairs(players) do
        local character = player.character --[[@as LuaEntity]]
        if util.distance(character.position, ruin.position) <= REACH
          and (player.force --[[@as LuaForce]]).is_chunk_charted(surface, util.chunk_of(ruin.position)) then
          candidates[#candidates + 1] = ruin
          break
        end
      end
    end
  end
  return candidates[math.random(#candidates)]
end

---@param surface LuaSurface
---@param ruin LuaEntity
local function wake(surface, ruin)
  storage.storms.woken[ruin.unit_number] = true
  strike(surface, ruin.position)
  local awake = {
    entity = ruin,
    light = rendering.draw_light({ sprite = "utility/light_medium", target = ruin, surface = surface, scale = 6,
      intensity = 0.9, color = GLOW }),
    tags = {},
    next_strike = game.tick + STRIKE_SECONDS * 60,
  }
  storage.storms.awake[ruin.unit_number] = awake
  surface.spill_item_stack({
    position = util.offset(ruin.position, math.random() * 2 * math.pi, 3),
    stack = { name = cfg.SHARD, count = 1 },
    enable_looted = true,
    allow_belts = false,
  })
  local x, y = util.xy(ruin.position)
  local told = {}
  for _, player in ipairs(players_on(surface)) do
    local force = player.force --[[@as LuaForce]]
    if not told[force.index] then
      told[force.index] = true
      awake.tags[#awake.tags + 1] = force.add_chart_tag(surface, { position = ruin.position, icon = { type = "item", name = cfg.SHARD } })
      util.say(force, { "nexus-bosses.msg-ruin-wakes", math.floor(x), math.floor(y), surface.name }, util.COLORS.info)
    end
  end
end

---@param awake table
local function put_to_sleep(awake)
  if awake.light and awake.light.valid then
    awake.light.destroy()
  end
  for _, tag in ipairs(awake.tags) do
    if tag.valid then
      tag.destroy()
    end
  end
end

local function end_storm()
  for _, awake in pairs(storage.storms.awake) do
    put_to_sleep(awake)
  end
  storage.storms.awake = {}
  storage.storms.woken = {}
end

---Once a second.
---@param tick integer
function M.on_second(tick)
  local s = storage.storms
  local surface = util.nexus()
  if not surface then
    return
  end
  local raging = util.storm_active()
  if not raging then
    if s.raging then
      s.raging = false
      end_storm()
    end
    return
  end
  if not s.raging then
    s.raging = true
    s.next_wake = tick + WAKE_SECONDS * 60
  end
  local count = 0
  for unit, awake in pairs(s.awake) do
    local ruin = awake.entity
    if not ruin.valid then
      put_to_sleep(awake)
      s.awake[unit] = nil
    else
      count = count + 1
      rendering.draw_sprite({
        sprite = "nexus-bosses-spark",
        target = { entity = ruin, offset = { (math.random() - 0.5) * 3, -1 - math.random() * 2 } },
        surface = surface,
        tint = GLOW,
        x_scale = 1.5,
        y_scale = 1.5,
        orientation = math.random(),
        render_layer = "air-object",
        time_to_live = 60,
      })
      if tick >= awake.next_strike then
        awake.next_strike = tick + STRIKE_SECONDS * 60
        strike(surface, util.offset(ruin.position, math.random() * 2 * math.pi, math.random() * STRIKE_RADIUS))
      end
    end
  end
  if tick >= s.next_wake and count < MAX_AWAKE then
    s.next_wake = tick + WAKE_SECONDS * 60
    local ruin = pick_ruin(surface)
    if ruin then
      wake(surface, ruin)
    end
  end
end

---For tests: wakes the ruin nearest to a position, storm or not.
---@param position MapPosition
---@return boolean
function M.wake_nearest(position)
  local surface = util.nexus()
  local best, best_distance
  for _, ruin in pairs(storage.storms.ruins) do
    if ruin.valid and not storage.storms.awake[ruin.unit_number] then
      local distance = util.distance(position, ruin.position)
      if not best_distance or distance < best_distance then
        best, best_distance = ruin, distance
      end
    end
  end
  if not (surface and best) then
    return false
  end
  wake(surface, best)
  return true
end

---@return table
function M.snapshot()
  local ruins, awake = 0, {}
  for _ in pairs(storage.storms.ruins) do
    ruins = ruins + 1
  end
  for unit, entry in pairs(storage.storms.awake) do
    awake[#awake + 1] = { unit = unit, x = entry.entity.valid and entry.entity.position.x or nil,
      y = entry.entity.valid and entry.entity.position.y or nil }
  end
  return { ruins = ruins, awake = awake, raging = storage.storms.raging == true }
end

return M
