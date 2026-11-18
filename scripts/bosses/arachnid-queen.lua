-- Arachnid Queen: comes with two leviathans. At two thirds and at one third of her health she lays two nests; a nest
-- keeps four warriors and spitters at its side and sends them at the base every 20 seconds until it is broken.

local cfg = require("lib.nb_data")
local util = require("scripts.nb_util")
local records = require("scripts.nb_records")
local spawn = require("scripts.nb_spawn")
local telegraph = require("scripts.nb_telegraph")

local M = {}

local LEVIATHAN = "arachnid-biter-leviathan-unit"
local LEVIATHANS = 2
local ESCORT_RADIUS = 14
local NEST_THRESHOLDS = { 2 / 3, 1 / 3 }
local NESTS_PER_CLUTCH = 2
local NEST_SORTIE_SECONDS = 20
local NEST_TELEGRAPH_TICKS = 4 * 60
local NEST_MIN_SPACING = 4

---@param summon table
---@param surface LuaSurface
---@return boolean ok
---@return string|nil message_key
function M.spawn(summon, surface)
  local position = spawn.find_position(summon, surface, cfg.QUEEN)
  local queen = position and spawn.create_unit(surface, cfg.QUEEN, position)
  if not queen then
    return false, "msg-fail-position"
  end
  records.add(summon, queen, true, "boss")
  local units = { queen }
  for _ = 1, LEVIATHANS do
    local spot = surface.find_non_colliding_position(LEVIATHAN, queen.position, ESCORT_RADIUS, 1)
    local unit = spot and spawn.create_unit(surface, LEVIATHAN, spot)
    if unit then
      records.add(summon, unit, false, "escort")
      units[#units + 1] = unit
    end
  end
  summon.queen = { clutches = 0 }
  spawn.dispatch(surface, units, summon.position)
  return true, nil
end

---@param summon table
---@return integer
local function nest_count(summon)
  local weaken = summon.weaken or 0
  if weaken >= 1 then
    return 0
  end
  local count = math.floor(NESTS_PER_CLUTCH * (1 - weaken) + 0.5)
  return count + (summon.lair and 1 or 0)
end

---@param summon table
---@param surface LuaSurface
---@param queen LuaEntity
---@param count integer
local function telegraph_nests(summon, surface, queen, count)
  local positions = {}
  local attempts = 0
  while #positions < count and attempts < count * 12 do
    attempts = attempts + 1
    local center = queen.position
    if #positions > 0 then
      center = util.offset(queen.position, math.random() * 2 * math.pi, math.random() * 8)
    end
    local position = surface.find_non_colliding_position(cfg.QUEEN_NEST, center, 12, 1)
    local separated = position ~= nil
    for _, reserved in ipairs(positions) do
      if position and util.distance(position, reserved) < NEST_MIN_SPACING then
        separated = false
        break
      end
    end
    if position and separated then
      position = util.copy_position(position)
      positions[#positions + 1] = position
      telegraph.filling_circle(summon, surface, position, 4, NEST_TELEGRAPH_TICKS)
    end
  end
  telegraph.queue(summon, "nests", NEST_TELEGRAPH_TICKS, { positions = positions })
end

---@param summon table
---@param surface LuaSurface
---@param force LuaForce
---@param positions MapPosition[]
local function lay_nests(summon, surface, force, positions)
  local laid = 0
  for _, position in ipairs(positions) do
    local nest = surface.create_entity({ name = cfg.QUEEN_NEST, position = position, force = "enemy" })
    if nest then
      records.add(summon, nest, false, "nest")
      laid = laid + 1
    end
  end
  if laid > 0 then
    local x, y = util.xy(positions[1])
    util.say(force, { "nexus-bosses.msg-queen-nests", math.floor(x), math.floor(y), surface.name }, util.COLORS.warning)
    util.play(force, "queen-nests")
  end
end

---@param summon table
---@param surface LuaSurface
---@param _force LuaForce
function M.tick(summon, surface, _force)
  local seconds = summon.active_seconds
  if seconds % spawn.REDISPATCH_SECONDS == 0 then
    spawn.redispatch(summon, surface, records.commandable_units(summon))
  end

  local record = records.main(summon)
  local state = summon.queen
  local threshold = NEST_THRESHOLDS[state.clutches + 1]
  if record and threshold and record.entity.health <= record.initial * threshold then
    state.clutches = state.clutches + 1
    local count = nest_count(summon)
    if count > 0 then
      telegraph_nests(summon, surface, record.entity, count)
    end
  end

  if seconds % NEST_SORTIE_SECONDS == 0 then
    for _, nest in ipairs(records.of_role(summon, "nest")) do
      spawn.send_spawner_units(summon, surface, nest.entity)
    end
  end
end

---@param summon table
---@param surface LuaSurface
---@param force LuaForce
---@param entry NbPending
function M.on_pending(summon, surface, force, entry)
  if entry.kind == "nests" then
    lay_nests(summon, surface, force, entry.data.positions)
  end
end

---@param summon table
---@return LocalisedString|nil
function M.status(summon)
  local nests = #records.of_role(summon, "nest")
  if nests > 0 then
    return { "nexus-bosses.status-queen-nests", nests }
  end
  return nil
end

---The queen is dead: her nests die with her.
---@param summon table
function M.on_victory(summon)
  for _, nest in ipairs(records.of_role(summon, "nest")) do
    nest.entity.die()
  end
end

return M
