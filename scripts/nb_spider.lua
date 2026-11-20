-- Fuel and ammo for the mod's spider-vehicles, and autopilot routes toward a target.

local M = {}
local util = require("scripts.nb_util")

local APPROACH_STAND_OFF = 30

---Adds 20 solid fuel when fewer than 20 are stored, then inserts the supplied ammunition stacks.
---@param spider LuaEntity
---@param ammo {name: string, count: integer}[]
function M.supply(spider, ammo)
  if not spider.valid then
    return
  end
  local fuel = spider.get_fuel_inventory()
  if fuel then
    local count = fuel.get_item_count("solid-fuel")
    if count < 20 then
      fuel.insert({ name = "solid-fuel", count = 20 - count })
    end
  end
  local ammunition = spider.get_inventory(defines.inventory.spider_ammo)
  if ammunition then
    for _, stack in ipairs(ammo) do
      ammunition.insert(stack)
    end
  end
end

---Clears the current route and walks to a point near the target, 30 tiles away by default.
---@param spider LuaEntity
---@param target LuaEntity|MapPosition
---@param stand_off number|nil tiles to stop from target; defaults to 30
function M.approach(spider, target, stand_off)
  if not spider.valid then
    return
  end
  local distance = stand_off or APPROACH_STAND_OFF
  local position = target.position or target
  ---@cast position MapPosition
  local sx, sy = util.xy(spider.position)
  local tx, ty = util.xy(position)
  local dx, dy = sx - tx, sy - ty
  local length = math.sqrt(dx * dx + dy * dy)
  if length == 0 then
    dx, dy, length = 1, 0, 1
  end
  local destination = {
    x = tx + dx / length * distance,
    y = ty + dy / length * distance,
  }
  spider.autopilot_destination = nil
  spider.add_autopilot_destination(destination)
end

return M
