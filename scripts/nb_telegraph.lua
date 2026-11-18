-- Shared ground warnings for attacks. The rendering objects expire with the attack; this module keeps no state.

local M = {}

local COLOR = { r = 1, g = 0.25, b = 0.15, a = 0.6 }
local SOUND = "nexus-bosses-telegraph"

---@param target MapPosition|LuaEntity
---@return MapPosition
local function position_of(target)
  return target.position or target
end

---@param surface LuaSurface
---@param target MapPosition|LuaEntity
local function play(surface, target)
  surface.play_sound({ path = SOUND, position = position_of(target) })
end

---A circle outline and filled disk on the ground that last until the attack.
---@param surface LuaSurface
---@param target MapPosition|LuaEntity
---@param radius number
---@param ticks integer how long until the attack
---@return LuaRenderObject
function M.circle(surface, target, radius, ticks)
  play(surface, target)
  rendering.draw_circle({
    color = COLOR,
    radius = radius,
    width = 2,
    filled = false,
    target = target,
    surface = surface,
    draw_on_ground = true,
    blink_interval = 0,
    time_to_live = ticks,
  })
  return rendering.draw_circle({
    color = COLOR,
    radius = radius,
    width = 2,
    filled = true,
    target = target,
    surface = surface,
    draw_on_ground = true,
    blink_interval = 0,
    time_to_live = ticks,
  })
end

---A filled circle that grows to its attack radius while its outline stays visible.
---@param summon table
---@param surface LuaSurface
---@param target MapPosition|LuaEntity
---@param radius number
---@param ticks integer how long until the attack
function M.filling_circle(summon, surface, target, radius, ticks)
  local disk = M.circle(surface, target, radius, ticks)
  disk.radius = 0.1
  summon.renders = summon.renders or {}
  summon.renders[#summon.renders + 1] = {
    render = disk,
    radius = radius,
    start_tick = game.tick,
    end_tick = game.tick + ticks,
  }
end

---A line from an entity or position to a target.
---@param surface LuaSurface
---@param from MapPosition|LuaEntity
---@param to MapPosition|LuaEntity
---@param ticks integer how long until the attack
---@return LuaRenderObject
function M.line(surface, from, to, ticks)
  play(surface, to)
  return rendering.draw_line({
    color = COLOR,
    width = 3,
    from = from,
    to = to,
    surface = surface,
    blink_interval = 0,
    time_to_live = ticks,
  })
end

---A ring around an entity.
---@param surface LuaSurface
---@param entity LuaEntity
---@param radius number
---@param ticks integer how long until the attack
---@return LuaRenderObject
function M.ring(surface, entity, radius, ticks)
  play(surface, entity)
  return rendering.draw_circle({
    color = COLOR,
    radius = radius,
    width = 3,
    filled = false,
    target = entity,
    surface = surface,
    draw_on_ground = true,
    blink_interval = 0,
    time_to_live = ticks,
  })
end

return M
