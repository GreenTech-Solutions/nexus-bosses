-- Big Monsters (remote interface "bigmonster", 2.2.1).
--
-- create_event(event, surface, force) makes its boss at once, but only while a connected player of the force has a
-- character on the surface. It places the boss by walking from the spawn of the force along a random line through
-- generated chunks (FindTeamAttackCorner) until it meets 4 chunks without buildings (10 for the ultimate boss) and then
-- an ungenerated one: with too little generated land it makes nothing and says nothing, so the land is requested from
-- the map generator while the countdown runs. Once the boss is there, this mod moves it to the side of the trial,
-- scales its health and sends it to the beacon, like its own bosses.
--
-- At evolution 0.9 and above Big Monsters sets the health of its bosses to (0.2 + 0.1 * players * evolution * 1.5) of
-- the maximum: about 35 % for one player on Nexus.
--
-- Its random events go to the surfaces in its list. Nexus is never in it. The map setting
-- "nexus-bosses-big-monsters-beacons-only" takes the others out, so that its bosses come only from the beacons, and
-- puts back the ones it took when switched off.

local cfg = require("lib.nb_data")
local records = require("scripts.nb_records")
local spawn = require("scripts.nb_spawn")

local M = {}

local INTERFACE = "bigmonster"
local REDISPATCH_SECONDS = 45

---A call into the other mod: an error there must not stop this one.
---@return boolean ok
---@return any result_or_error
local function call(function_name, ...)
  local arguments = { ... }
  return pcall(function() ---@diagnostic disable-line: redundant-return-value
    return remote.call(INTERFACE, function_name, table.unpack(arguments))
  end)
end

---The surfaces Big Monsters sends its random events to (its list starts with Nauvis and lets in these planets when
---their surfaces are created, if its setting bm-spawn_on_sa_planets is on).
---@param name string
---@return boolean
local function bm_surface(name)
  if name == "nauvis" then
    return true
  end
  local sa = settings.global["bm-spawn_on_sa_planets"]
  return sa ~= nil and sa.value == true and (name == "fulgora" or name == "gleba" or name == "vulcanus")
end

---Applies the map setting: Big Monsters' random events nowhere, or back where they were.
function M.apply_planets_setting()
  storage.bm_excluded = storage.bm_excluded or {}
  call("remove_planet", cfg.PLANET)
  call("exclude_surface", cfg.PLANET)
  if settings.global["nexus-bosses-big-monsters-beacons-only"].value then
    for _, surface in pairs(game.surfaces) do
      M.on_surface_created(surface)
    end
  else
    for name in pairs(storage.bm_excluded) do
      if game.get_surface(name) then
        call("add_surface", name)
      end
    end
    storage.bm_excluded = {}
  end
end

---A surface was created (Big Monsters, a dependency, has already taken it in): with the setting on it goes out.
---@param surface LuaSurface
function M.on_surface_created(surface)
  if settings.global["nexus-bosses-big-monsters-beacons-only"].value and bm_surface(surface.name)
    and not storage.bm_excluded[surface.name] then
    storage.bm_excluded[surface.name] = true
    call("exclude_surface", surface.name)
  end
end

---@param surface LuaSurface
---@param force LuaForce
---@param chunks integer
function M.request_land(surface, force, chunks)
  surface.request_to_generate_chunks(force.get_spawn_position(surface), chunks)
end

---@param boss_id string
---@return NbBmSet
function M.set_of(boss_id)
  return cfg.BOSSES[boss_id].bm --[[@as NbBmSet]]
end

---Names of the boss prototypes of an event: entity types and name prefixes (corpses have other types).
---@param boss_id string
---@return string[]
function M.boss_names(boss_id)
  local set = M.set_of(boss_id)
  local names = {}
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

---Unit numbers of the boss entities already on the surface.
---@param surface LuaSurface
---@param names string[]
---@return table<integer, boolean>
function M.snapshot(surface, names)
  local known = {}
  for _, entity in ipairs(surface.find_entities_filtered({ name = names, force = "enemy" })) do
    known[entity.unit_number] = true
  end
  return known
end

---@param surface LuaSurface
---@param names string[]
---@param known table<integer, boolean>
---@return LuaEntity[] the boss entities that were not there before
function M.find_new(surface, names, known)
  local found = {}
  for _, entity in ipairs(surface.find_entities_filtered({ name = names, force = "enemy" })) do
    if not known[entity.unit_number] then
      found[#found + 1] = entity
    end
  end
  return found
end

---@param event string
---@param surface LuaSurface
---@param force LuaForce
---@return string|nil error
function M.call_event(event, surface, force)
  call("add_player_force", force.name)
  local ok, err = call("create_event", event, surface.name, force.name)
  return not ok and tostring(err) or nil
end

---A boss of Big Monsters has appeared: it goes to the side of the trial with the health of the setting, and marches.
---@param summon table
---@param surface LuaSurface
---@param entity LuaEntity
function M.adopt(summon, surface, entity)
  local position = spawn.find_position(summon, surface, entity.name)
  if position then
    entity.teleport(position)
  end
  local health = settings.startup["nexus-bosses-boss-health"].value --[[@as number]]
  entity.health = math.min(entity.max_health, (entity.health --[[@as number]]) * health)
  records.add(summon, entity, true, "boss")
  if entity.type == "spider-vehicle" then
    -- Big Monsters moves its spiders itself, every 18 seconds, to the nearest enemy
    entity.autopilot_destination = summon.position
  else
    spawn.dispatch(surface, { entity }, summon.position)
  end
end

---@param summon table
---@param surface LuaSurface
function M.tick(summon, surface)
  if summon.active_seconds % REDISPATCH_SECONDS == 0 then
    spawn.redispatch(summon, surface, records.commandable_units(summon))
  end
end

return M
