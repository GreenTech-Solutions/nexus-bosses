-- Arachnid Queen: comes with two leviathans. At two thirds and at one third of her health she lays two nests; a nest
-- keeps four warriors and spitters at its side and sends them at the base every 20 seconds until it is broken.

local cfg = require("lib.nb_data")
local util = require("scripts.nb_util")
local records = require("scripts.nb_records")
local spawn = require("scripts.nb_spawn")

local M = {}

local LEVIATHAN = "arachnid-biter-leviathan-unit"
local LEVIATHANS = 2
local ESCORT_RADIUS = 14
local NEST_THRESHOLDS = { 2 / 3, 1 / 3 }
local NESTS_PER_CLUTCH = 2
local NEST_SORTIE_SECONDS = 20
local REDISPATCH_SECONDS = 45

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
---@param surface LuaSurface
---@param force LuaForce
---@param queen LuaEntity
local function lay_nests(summon, surface, force, queen)
  local laid = 0
  for _ = 1, NESTS_PER_CLUTCH do
    local spot = surface.find_non_colliding_position(cfg.QUEEN_NEST, queen.position, 12, 1)
    local nest = spot and surface.create_entity({ name = cfg.QUEEN_NEST, position = spot, force = "enemy" })
    if nest then
      records.add(summon, nest, false, "nest")
      laid = laid + 1
    end
  end
  if laid > 0 then
    local x, y = util.xy(queen.position)
    util.say(force, { "nexus-bosses.msg-queen-nests", math.floor(x), math.floor(y), surface.name }, util.COLORS.warning)
    util.play(force, util.SOUND_ALARM)
  end
end

---@param summon table
---@param surface LuaSurface
---@param force LuaForce
function M.tick(summon, surface, force)
  local seconds = summon.active_seconds
  if seconds % REDISPATCH_SECONDS == 0 then
    spawn.redispatch(summon, surface, records.commandable_units(summon))
  end

  local record = records.main(summon)
  local state = summon.queen
  local threshold = NEST_THRESHOLDS[state.clutches + 1]
  if record and threshold and record.entity.health <= record.initial * threshold then
    state.clutches = state.clutches + 1
    lay_nests(summon, surface, force, record.entity)
  end

  if seconds % NEST_SORTIE_SECONDS == 0 then
    for _, nest in ipairs(records.of_role(summon, "nest")) do
      local target = spawn.nearest_building(surface, nest.entity.position, summon)
      local destination = target and target.position or summon.position
      for _, unit in ipairs(nest.entity.units) do
        unit.commandable.set_command(spawn.attack_command(destination))
      end
    end
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
