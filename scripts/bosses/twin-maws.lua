-- Twin Maws: a fire worm and an acid worm of Big Monsters burrow up 45-65 tiles from the beacon, on the side of the
-- trial, a little apart. They do not move: they outrange most turrets, so the fight is taken to them.

local cfg = require("lib.nb_data")
local util = require("scripts.nb_util")
local records = require("scripts.nb_records")
local telegraph = require("scripts.nb_telegraph")

local M = {}

local DISTANCE_MIN = 45
local DISTANCE_MAX = 65
local SPREAD = 0.35 -- radians between the two
local MUTUAL_HEAL_SHARE = 0.003
local RISE_SECONDS = 20
local RISE_RADIUS = 4

---@param surface LuaSurface
---@param position MapPosition
local function burrow_effect(surface, position)
  surface.create_entity({ name = "bm-large-tunnel", position = position, force = "neutral" })
  surface.create_entity({ name = "big-demolisher-fissure-explosion", position = position })
end

---@param summon NbSummon
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
  local main_position = records.position(summon.tracked[1])
  summon.spawn_distance = main_position and util.distance(main_position, summon.position) or nil
  summon.maws = {}
  return true, nil
end

---@param summon NbSummon
---@param surface LuaSurface
---@param _force LuaForce
function M.tick(summon, surface, _force)
  summon.maws = summon.maws or {}
  local living = records.of_role(summon, "boss")
  if #living == 2 then
    local heal_share = MUTUAL_HEAL_SHARE * (1 - (summon.weaken or 0))
    for _, record in ipairs(living) do
      local entity = record.entity
      entity.health = math.min(entity.max_health, entity.health + entity.max_health * heal_share)
    end
    return
  end
  if #living ~= 1 or summon.maws.fallen or (summon.weaken or 0) >= 1 then
    return
  end

  for _, record in ipairs(summon.tracked) do
    if record.role == "boss" and record.dead and record.death_position then
      local position = util.copy_position(record.death_position)
      summon.maws.fallen = {
        name = record.name,
        position = position,
        max_health = record.death_max_health or record.initial,
      }
      local delay = math.floor(RISE_SECONDS * 60 / (summon.frequency or 1) + 0.5)
      telegraph.circle(summon, surface, position, RISE_RADIUS, delay)
      telegraph.queue(summon, "rise", delay, {})
      return
    end
  end
end

---@param summon NbSummon
---@param surface LuaSurface
---@param _force LuaForce
---@param entry NbPending
function M.on_pending(summon, surface, _force, entry)
  if entry.kind ~= "rise" then
    return
  end
  summon.maws = summon.maws or {}
  local fallen = summon.maws.fallen
  if not fallen then
    return
  end

  local second_alive = false
  local old_record
  for _, record in ipairs(summon.tracked) do
    if record.role == "boss" and record.name == fallen.name then
      old_record = record
    elseif record.role == "boss" and records.alive(record) then
      second_alive = true
    end
  end
  if not (second_alive and old_record) then
    summon.maws.fallen = nil
    return
  end

  local maw = surface.create_entity({ name = fallen.name, position = fallen.position, force = "enemy" })
  if not maw then
    summon.maws.fallen = nil
    return
  end
  maw.health = fallen.max_health / 2
  records.replace(summon, old_record, maw)
  burrow_effect(surface, maw.position)
  summon.maws.fallen = nil
end

---@param summon NbSummon
---@return LocalisedString|nil
function M.status(summon)
  local fallen = summon.maws and summon.maws.fallen
  local function health_percent(name)
    for _, record in ipairs(summon.tracked) do
      if record.role == "boss" and record.name == name then
        if record.dead or record.gone or not record.entity.valid then
          return 0
        end
        local max_health = record.entity.max_health or record.death_max_health or record.initial
        local current_health = record.entity.health
        return current_health and max_health > 0 and math.floor(current_health / max_health * 100 + 0.5) or 0
      end
    end
    return 0
  end

  ---@type LocalisedString
  local health = {
    "nexus-bosses.status-maws-health",
    { "entity-name." .. cfg.MAW_FIRE },
    health_percent(cfg.MAW_FIRE),
    { "entity-name." .. cfg.MAW_ACID },
    health_percent(cfg.MAW_ACID),
  }
  ---@type LocalisedString
  local previous = { "nexus-bosses.status-maws-healing" }
  if fallen then
    for _, entry in ipairs(summon.pending or {}) do
      if entry.kind == "rise" then
        previous = { "nexus-bosses.status-maws-rise", math.max(0, math.ceil((entry.at - game.tick) / 60)) }
        break
      end
    end
  end
  return { "", health, " · ", previous }
end

return M
