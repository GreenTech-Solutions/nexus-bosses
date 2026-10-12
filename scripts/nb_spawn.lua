-- What every boss needs: a place 150-250 tiles from the beacon on the side the trial comes from, units that keep
-- living when their commands fail, orders against the player's base, and the precursor waves of the countdown.

local cfg = require("lib.nb_data")
local util = require("scripts.nb_util")

local M = {}

M.SPAWN_MIN = 150
M.SPAWN_MAX = 250
local PRECURSOR_MIN = 90
local PRECURSOR_MAX = 120
local ATTACK_RADIUS = 45
local BUILDING_SEARCH_RADIUS = 600

---@param surface LuaSurface
---@param name string
---@param position MapPosition
---@return LuaEntity|nil
function M.create_unit(surface, name, position)
  local unit = surface.create_entity({ name = name, position = position, force = "enemy" })
  if unit then
    local ai = unit.ai_settings
    if ai then
      ai.allow_destroy_when_commands_fail = false
      ai.allow_try_return_to_spawner = false
    end
  end
  return unit
end

---The nearest building of the player around the beacon that enemies care about.
---@param surface LuaSurface
---@param position MapPosition where the attacker is
---@param summon table
---@return LuaEntity|nil
function M.nearest_building(surface, position, summon)
  -- The ruins of Fulgora on Nexus belong to the player force and can be military targets, but nobody built them:
  -- last_user tells them apart. Only military targets: a large base has tens of thousands of belts and poles.
  local targets = surface.find_entities_filtered({
    position = summon.position,
    radius = BUILDING_SEARCH_RADIUS,
    force = summon.force,
    is_military_target = true,
  })
  local nearest, nearest_distance
  for _, target in ipairs(targets) do
    if target.last_user and target.type ~= "lightning-attractor" then
      local distance = util.distance(position, target.position)
      if not nearest_distance or distance < nearest_distance then
        nearest, nearest_distance = target, distance
      end
    end
  end
  return nearest
end

---@param target MapPosition
---@return Command
function M.attack_command(target)
  return {
    type = defines.command.compound,
    structure_type = defines.compound_command.return_last,
    commands = {
      {
        type = defines.command.attack_area,
        destination = target,
        radius = ATTACK_RADIUS,
        distraction = defines.distraction.by_anything,
      },
      { type = defines.command.wander, radius = ATTACK_RADIUS, distraction = defines.distraction.by_enemy },
    },
  }
end

---Sends units against the target: walkers as one group, flyers as another (a group keeps the pace of the slowest).
---@param surface LuaSurface
---@param units LuaEntity[]
---@param target MapPosition
function M.dispatch(surface, units, target)
  ---@type LuaEntity[], LuaEntity[]
  local walkers, flyers = {}, {}
  for _, unit in ipairs(units) do
    if unit.valid and unit.commandable then
      local batch = unit.name:find("^flying%-") and flyers or walkers
      batch[#batch + 1] = unit
    end
  end
  for _, members in ipairs({ walkers, flyers }) do
    if #members > 0 then
      local group = surface.create_unit_group({ position = members[1].position, force = members[1].force })
      for _, unit in ipairs(members) do
        group.add_member(unit)
      end
      group.set_command(M.attack_command(target))
      group.start_moving()
    end
  end
end

---New orders for the units of the trial: the nearest building, or the beacon when there is none.
---@param summon table
---@param surface LuaSurface
---@param units LuaEntity[]
function M.redispatch(summon, surface, units)
  if #units == 0 then
    return
  end
  local target = M.nearest_building(surface, units[1].position, summon)
  M.dispatch(surface, units, target and target.position or summon.position)
end

---A place for the boss on the side of the trial. What was not perfect about it is kept for the state of the remote
---interface and said in the chat.
---@param summon table
---@param surface LuaSurface
---@param name string entity prototype
---@return MapPosition|nil
function M.find_position(summon, surface, name)
  local position, note = util.find_spawn_position(surface, summon.position, summon.angle, name, M.SPAWN_MIN,
    M.SPAWN_MAX, summon.force)
  if position then
    summon.spawn_distance = util.distance(position, summon.position)
    summon.spawn_note = note
  end
  return position
end

---Asks the map generator for the ring where the boss will appear, while the countdown runs: by its end the chunks
---exist and the search does not generate them in one tick.
---@param surface LuaSurface
---@param position MapPosition
function M.request_land(surface, position)
  surface.request_to_generate_chunks(position, math.ceil(M.SPAWN_MAX / 32) + 1)
end

---A wave of the countdown: units of the boss's kind come from its side for the beacon.
---@param summon table
---@param surface LuaSurface
---@return MapPosition|nil where they come from
function M.precursor_wave(summon, surface)
  local boss = cfg.BOSSES[summon.boss]
  local count = cfg.CIRCLES[boss.circle].precursors
  local names = boss.precursors
  local origin = util.offset(summon.position, summon.angle + (math.random() - 0.5) * 0.4,
    PRECURSOR_MIN + math.random() * (PRECURSOR_MAX - PRECURSOR_MIN))
  util.ensure_generated(surface, origin)
  local units = {}
  for index = 1, count do
    local name = names[(index - 1) % #names + 1]
    local spot = surface.find_non_colliding_position(name, origin, 16, 1)
    local unit = spot and M.create_unit(surface, name, spot)
    if unit then
      units[#units + 1] = unit
    end
  end
  if #units == 0 then
    return nil
  end
  M.dispatch(surface, units, summon.position)
  return origin
end

return M
