-- Devourer: a demolisher of 5 million health that claims the land around the beacon (a territory of five by five
-- chunks). Every 15 seconds it is set "enraged" against the nearest building of the player, the strongest order the API
-- has for a segmented unit. At half of its health it dives and, eight seconds later, breaks out on the far side of the
-- beacon with the health it had.

local cfg = require("lib.nb_data")
local util = require("scripts.nb_util")
local records = require("scripts.nb_records")
local spawn = require("scripts.nb_spawn")

local M = {}

local TERRITORY_CHUNK_RADIUS = 2
local ORDER_SECONDS = 15
local DIVE_SHARE = 0.5
local DIVE_SECONDS = 8
local SURFACE_DISTANCE = 80

---@param surface LuaSurface
---@param center MapPosition
---@return LuaTerritory|nil
local function create_territory(surface, center)
  local origin = util.chunk_of(center)
  local chunks = {}
  for x = origin.x - TERRITORY_CHUNK_RADIUS, origin.x + TERRITORY_CHUNK_RADIUS do
    for y = origin.y - TERRITORY_CHUNK_RADIUS, origin.y + TERRITORY_CHUNK_RADIUS do
      if surface.is_chunk_generated({ x = x, y = y }) then
        chunks[#chunks + 1] = { x = x, y = y }
      end
    end
  end
  if #chunks == 0 then
    return nil
  end
  return surface.create_territory({ chunks = chunks })
end

---@param surface LuaSurface
---@param position MapPosition
---@param summon table
---@return LuaSegmentedUnit|nil
local function create_worm(surface, position, summon)
  local worm = surface.create_segmented_unit({
    name = cfg.DEVOURER,
    position = position,
    direction = util.direction_toward(position, summon.position),
    force = "enemy",
    territory = summon.devourer.territory,
  })
  if worm then
    -- nobody may be near it for a while: the engine must not put it to sleep
    worm.minimum_activity_mode = defines.segmented_unit_activity_mode.minimal
  end
  return worm
end

---@param summon table
---@param surface LuaSurface
---@param worm LuaSegmentedUnit
local function give_orders(summon, surface, worm)
  local head = worm.get_body_nodes()[1]
  local target = spawn.nearest_building(surface, head, summon)
  if target then
    worm.set_ai_state({
      type = defines.segmented_unit_ai_state.enraged_at_target,
      target = target,
      attacked_me = true,
      last_damage_time = game.tick,
    })
  else
    worm.set_ai_state({ type = defines.segmented_unit_ai_state.investigating, destination = summon.position })
  end
end

---@param summon table
---@param surface LuaSurface
---@return boolean ok
---@return string|nil message_key
function M.spawn(summon, surface)
  local position = spawn.find_position(summon, surface, cfg.DEVOURER)
  if not position then
    return false, "msg-fail-position"
  end
  summon.devourer = { territory = create_territory(surface, summon.position), dived = false }
  local worm = create_worm(surface, position, summon)
  if not worm then
    return false, "msg-fail-position"
  end
  records.add(summon, worm, true, "boss", true)
  give_orders(summon, surface, worm)
  return true, nil
end

---@param summon table
---@param surface LuaSurface
---@param force LuaForce
---@param record table
local function dive(summon, surface, force, record)
  local worm = record.entity
  local head = util.copy_position(worm.get_body_nodes()[1])
  record.hidden = true
  record.hidden_health = worm.health
  local state = summon.devourer
  state.dived = true
  state.rise_tick = game.tick + DIVE_SECONDS * 60
  -- the far side of the beacon from where it went down
  local away = math.atan2(summon.position.y - head.y, summon.position.x - head.x)
  state.rise_at = util.offset(summon.position, away, SURFACE_DISTANCE)
  surface.create_entity({ name = "big-demolisher-fissure-explosion", position = head })
  worm.destroy()
  util.say(force, { "nexus-bosses.msg-devourer-dives", DIVE_SECONDS }, util.COLORS.warning)
  util.play(force, "devourer-burrow")
end

---@param summon table
---@param surface LuaSurface
---@param force LuaForce
---@param record table
local function rise(summon, surface, force, record)
  local state = summon.devourer
  util.ensure_generated(surface, state.rise_at)
  local position = surface.find_non_colliding_position(cfg.DEVOURER, state.rise_at, 40, 1) or state.rise_at
  local worm = create_worm(surface, position, summon)
  if not worm then
    return -- tried again next second
  end
  worm.health = record.hidden_health
  records.replace(summon, record, worm)
  surface.create_entity({ name = "big-demolisher-fissure-explosion", position = position })
  state.rise_tick = nil
  give_orders(summon, surface, worm)
  local x, y = util.xy(position)
  util.say(force, { "nexus-bosses.msg-devourer-rises", math.floor(x), math.floor(y), surface.name }, util.COLORS.bad)
  util.play(force, "devourer-burrow")
end

---@param summon table
---@param surface LuaSurface
---@param force LuaForce
function M.tick(summon, surface, force)
  local record = summon.tracked[1]
  local state = summon.devourer
  if record.hidden then
    if game.tick >= state.rise_tick then
      rise(summon, surface, force, record)
    end
    return
  end
  if not records.alive(record) then
    return
  end
  if not state.dived and record.entity.health <= record.initial * DIVE_SHARE then
    dive(summon, surface, force, record)
    return
  end
  if summon.active_seconds % ORDER_SECONDS == 0 then
    give_orders(summon, surface, record.entity)
  end
end

---@param summon table
---@return LocalisedString|nil
function M.status(summon)
  if summon.tracked[1] and summon.tracked[1].hidden then
    return { "nexus-bosses.status-devourer-underground" }
  end
  return nil
end

---@param summon table
function M.on_victory(summon)
  local territory = summon.devourer.territory
  if territory and territory.valid then
    territory.destroy()
  end
end

---The trial ends without a victory: a living Devourer may sleep again; a territory that guards nothing goes.
---@param summon table
function M.release(summon)
  local record = summon.tracked[1]
  if record and not record.hidden and records.alive(record) then
    record.entity.minimum_activity_mode = nil
  end
  local territory = summon.devourer and summon.devourer.territory
  if territory and territory.valid and #territory.get_segmented_units() == 0 then
    territory.destroy()
  end
end

return M
