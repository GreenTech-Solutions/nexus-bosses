-- Twin Maws: a fire worm and an acid worm of Big Monsters burrow up 45-65 tiles from the beacon, on the side of the
-- trial, a little apart. They do not move: they outrange most turrets, so the fight is taken to them.

local cfg = require("lib.nb_data")
local util = require("scripts.nb_util")
local records = require("scripts.nb_records")

local M = {}

local DISTANCE_MIN = 45
local DISTANCE_MAX = 65
local SPREAD = 0.35 -- radians between the two

---@param surface LuaSurface
---@param position MapPosition
local function burrow_effect(surface, position)
  surface.create_entity({ name = "bm-large-tunnel", position = position, force = "neutral" })
  surface.create_entity({ name = "big-demolisher-fissure-explosion", position = position })
end

---@param summon table
---@param surface LuaSurface
---@return boolean ok
---@return string|nil message_key
function M.spawn(summon, surface)
  local placed = 0
  for index, name in ipairs({ cfg.MAW_FIRE, cfg.MAW_ACID }) do
    local angle = summon.angle + (index == 1 and -SPREAD or SPREAD)
    local wanted = util.offset(summon.position, angle, DISTANCE_MIN + math.random() * (DISTANCE_MAX - DISTANCE_MIN))
    util.ensure_generated(surface, wanted)
    local position = surface.find_non_colliding_position(name, wanted, 20, 1)
    local maw = position and surface.create_entity({ name = name, position = position, force = "enemy" })
    if maw then
      records.add(summon, maw, true, "boss")
      burrow_effect(surface, maw.position)
      placed = placed + 1
    end
  end
  if placed == 0 then
    return false, "msg-fail-position"
  end
  summon.spawn_distance = util.distance(summon.tracked[1].entity.position, summon.position)
  return true, nil
end

---@param summon table
---@return LocalisedString|nil
function M.status(summon)
  local alive = 0
  for _, record in ipairs(summon.tracked) do
    if record.required and records.alive(record) then
      alive = alive + 1
    end
  end
  return { "nexus-bosses.status-maws", alive }
end

return M
