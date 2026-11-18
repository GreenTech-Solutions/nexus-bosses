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
---@param summon table
---@param surface LuaSurface
---@param target MapPosition|LuaEntity
---@param radius number
---@param ticks integer how long until the attack
---@return LuaRenderObject
function M.circle(summon, surface, target, radius, ticks)
  play(surface, target)
  local outline = rendering.draw_circle({
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
  local disk = rendering.draw_circle({
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
  summon.renders = summon.renders or {}
  summon.renders[#summon.renders + 1] = { render = outline }
  summon.renders[#summon.renders + 1] = { render = disk }
  return disk
end

---A filled circle that grows to its attack radius while its outline stays visible.
---@param summon table
---@param surface LuaSurface
---@param target MapPosition|LuaEntity
---@param radius number
---@param ticks integer how long until the attack
function M.filling_circle(summon, surface, target, radius, ticks)
  local disk = M.circle(summon, surface, target, radius, ticks)
  disk.radius = 0.1
  local entry = summon.renders[#summon.renders]
  entry.radius = radius
  entry.start_tick = game.tick
  entry.end_tick = game.tick + ticks
end

---A line from an entity or position to a target.
---@param summon table
---@param surface LuaSurface
---@param from MapPosition|LuaEntity
---@param to MapPosition|LuaEntity
---@param ticks integer how long until the attack
---@return LuaRenderObject
function M.line(summon, surface, from, to, ticks)
  play(surface, to)
  local line = rendering.draw_line({
    color = COLOR,
    width = 3,
    from = from,
    to = to,
    surface = surface,
    blink_interval = 0,
    time_to_live = ticks,
  })
  summon.renders = summon.renders or {}
  summon.renders[#summon.renders + 1] = { render = line }
  return line
end

---A ring around an entity.
---@param summon table
---@param surface LuaSurface
---@param entity LuaEntity
---@param radius number
---@param ticks integer how long until the attack
---@return LuaRenderObject
function M.ring(summon, surface, entity, radius, ticks)
  play(surface, entity)
  local ring = rendering.draw_circle({
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
  summon.renders = summon.renders or {}
  summon.renders[#summon.renders + 1] = { render = ring }
  return ring
end

---Queues a boss strike. Data stays serializable; LuaEntity references are kept separately and checked when used.
---@param summon table
---@param kind string
---@param ticks integer
---@param data table|nil
---@param entities LuaEntity[]|nil
function M.queue(summon, kind, ticks, data, entities)
  summon.pending = summon.pending or {}
  summon.pending[#summon.pending + 1] = {
    at = game.tick + ticks,
    kind = kind,
    data = data or {},
    entities = entities,
  }
end

return M
