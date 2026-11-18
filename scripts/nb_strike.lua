-- Shared marks and rocket strikes used by bosses that target player buildings.

local util = require("scripts.nb_util")
local spawn = require("scripts.nb_spawn")
local telegraph = require("scripts.nb_telegraph")

local M = {}

local TELEGRAPH_RADIUS = 3
local ROCKET = "explosive-rocket"
local ROCKET_SPEED = 0.5

---Marks the nearest player building and queues a delayed rocket strike.
---@param summon NbSummon
---@param surface LuaSurface
---@param source LuaEntity
---@param radius number target search radius
---@param ticks integer warning duration
---@return boolean marked
function M.mark(summon, surface, source, radius, ticks)
  local target = spawn.nearest_target(surface, summon, source.position, radius, { building = true })
  if not target then
    return false
  end
  telegraph.line(summon, surface, source, target, ticks)
  telegraph.circle(summon, surface, target, TELEGRAPH_RADIUS, ticks)
  telegraph.queue(summon, "strike", ticks,
    { target = target.unit_number, position = util.copy_position(target.position) }, { target })
  return true
end

---Fires rockets at the building retained by a pending mark.
---@param surface LuaSurface
---@param source LuaEntity
---@param entry NbPending
---@param rockets integer
function M.fire(surface, source, entry, rockets)
  local target = entry.entities and entry.entities[1]
  if not (source.valid and target and target.valid) then
    return
  end
  for _ = 1, rockets do
    surface.create_entity({
      name = ROCKET,
      position = source.position,
      target = target,
      speed = ROCKET_SPEED,
      force = "enemy",
    })
  end
end

return M
