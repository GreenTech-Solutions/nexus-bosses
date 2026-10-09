-- Integration with Big-Monsters (remote interface "bigmonster").
--
-- What the mod relies on (Big-Monsters 2.2.1, control.lua):
--   create_event(event, surface_name, force_name) spawns the boss synchronously, but only when a connected player
--   of the force has a character on the surface, and only for forces listed in storage.player_forces; the place is
--   found by walking from the spawn of the force along a random line through generated chunks (FindTeamAttackCorner):
--   it needs a few chunks without buildings of the force (4, for the final boss 10) and then an ungenerated one, so
--   with too little generated land it creates nothing and says nothing. M.request_land asks the map generator for that
--   land.
--   remove_planet(name) takes a planet off the list of the Space Age planets that get random events.

local cfg = require("lib.nb_data")

local M = {}

local INTERFACE = "bigmonster"

---A protected call of a function of the interface: an error inside the other mod must not stop ours.
---@param function_name string
---@param first string|nil
---@param second string|nil
---@param third string|nil
---@return boolean ok
---@return any result_or_error
local function call(function_name, first, second, third)
  local ok, result = pcall(function()
    return remote.call(INTERFACE, function_name, first, second, third)
  end)
  return ok, result
end

---@return boolean
function M.available()
  local interface = remote.interfaces[INTERFACE]
  return interface ~= nil and interface.create_event ~= nil
end

---Takes planets off the list of Big-Monsters, the planets whose surfaces it adds to its events when they are created:
---Nexus always (its bosses come from the beacons only), every planet while the map setting
---"nexus-bosses-big-monsters-elsewhere-off" is on. Its runtime settings handler resets the list to Fulgora, Gleba and
---Vulcanus, so this runs again after every change of the settings.
function M.disable_planets()
  local interface = remote.interfaces[INTERFACE]
  if not (interface and interface.remove_planet) then
    return
  end
  if settings.global["nexus-bosses-big-monsters-elsewhere-off"].value then
    for planet_name in pairs(game.planets) do
      call("remove_planet", planet_name)
    end
  else
    call("remove_planet", cfg.PLANET)
  end
end

---Asks the map generator for the land around the spawn of the force, where Big-Monsters looks for a place for its
---boss. The generation is asynchronous and skips what exists already, so it is asked for when a summon starts (the
---countdown is the time it needs) and again at the launch.
---@param surface LuaSurface
---@param force LuaForce
---@param chunks integer chunk radius
---@return boolean true when the request was made
function M.request_land(surface, force, chunks)
  local ok, err = pcall(function()
    surface.request_to_generate_chunks(force.get_spawn_position(surface), chunks)
  end)
  if not ok then
    log("[nexus-bosses] cannot request the land around the spawn: " .. tostring(err))
  end
  return ok
end

---Names of the entity prototypes that belong to the bosses of a beacon: types and prefixes from cfg.BM_SETS.
---Corpses and everything else with the same prefix have other types and never match.
---@param boss_id string
---@return string[]
function M.boss_names(boss_id)
  local set = cfg.BM_SETS[boss_id]
  local names = {}
  if not set then
    return names
  end
  for name in pairs(prototypes.get_entity_filtered({ { filter = "type", type = set.types } })) do
    for _, prefix in ipairs(set.prefixes) do
      if name:sub(1, #prefix) == prefix then
        names[#names + 1] = name
        break
      end
    end
  end
  table.sort(names)
  return names
end

---Unit numbers of the boss entities that already stand on the surface.
---@param surface LuaSurface
---@param names string[]
---@return table<integer, boolean>
function M.snapshot(surface, names)
  local snapshot = {}
  if #names == 0 then
    return snapshot
  end
  for _, entity in ipairs(surface.find_entities_filtered({ name = names, force = "enemy" })) do
    if entity.valid and entity.unit_number then
      snapshot[entity.unit_number] = true
    end
  end
  return snapshot
end

---The boss entities that were not there before the first call of the event.
---@param surface LuaSurface
---@param names string[]
---@param known table<integer, boolean> the snapshot
---@return LuaEntity[]
function M.find_new(surface, names, known)
  local found = {}
  if #names == 0 then
    return found
  end
  for _, entity in ipairs(surface.find_entities_filtered({ name = names, force = "enemy" })) do
    local number = entity.unit_number
    if entity.valid and number and not known[number] then
      found[#found + 1] = entity
    end
  end
  return found
end

---Asks Big-Monsters for the event. The call is protected: an error inside the other mod must not stop ours.
---@param event string
---@param surface LuaSurface
---@param force LuaForce
---@return boolean ok
---@return string|nil error
function M.call_event(event, surface, force)
  -- make sure the force is one of those Big-Monsters attacks (a no-op for the default force)
  call("add_player_force", force.name)
  local ok, err = call("create_event", event, surface.name, force.name)
  if ok then
    return true, nil
  end
  return false, tostring(err)
end

return M
