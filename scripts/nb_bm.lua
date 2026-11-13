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
-- Its random events go to the surfaces in its list. This mod sets that list on every surface: with the map setting
-- "nexus-bosses-big-monsters-random-events" off (the default on every difficulty: its early bosses are too strong for a
-- start even on Nightmare) it is empty, so that its bosses come only from the beacons; with it on it is Nauvis, and
-- Fulgora, Gleba and Vulcanus while bm-spawn_on_sa_planets is on, as Big Monsters has it itself. Nexus is never in it.
-- A save that still has the old value "auto" gets "off".
--
-- Its other attacks do not look at the list: the attacks on rocket silos (bm-enable-silo-attack) hit every silo with a
-- player nearby on any surface. settings-updates.lua turns them off for good. As the last line, on_second() removes
-- its monsters from every surface outside the list within a second, whatever made them.

local cfg = require("lib.nb_data")
local records = require("scripts.nb_records")
local spawn = require("scripts.nb_spawn")
local util = require("scripts.nb_util")

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

---Whether Big Monsters' random events are off by the map setting.
---@return boolean
local function events_off()
  return settings.global["nexus-bosses-big-monsters-random-events"].value ~= "on"
end

---Whether Big Monsters may make its monsters on the surface: its random events are on, and the surface is one of its
---planets and not Nexus.
---@param name string
---@return boolean
function M.allowed_surface(name)
  return not events_off() and name ~= cfg.PLANET and bm_surface(name)
end

---Applies the map setting to Big Monsters' list of surfaces, surface by surface.
function M.apply_planets_setting()
  -- the surfaces that 2.5.5 and older took out of the list; every surface is set now
  storage.bm_excluded = nil
  call("remove_planet", cfg.PLANET)
  for _, surface in pairs(game.surfaces) do
    M.on_surface_created(surface)
  end
end

---A surface was created (Big Monsters, a dependency, has already taken it in, if it is one of its planets).
---@param surface LuaSurface
function M.on_surface_created(surface)
  call(M.allowed_surface(surface.name) and "add_surface" or "exclude_surface", surface.name)
end

-- The prototypes of Big Monsters' monsters: the bosses of its events and the invasions, worms and volcanoes it makes.
-- Not the small bosses maf-boss-biter-N and maf-boss-acid-spitter-N: the boss spawner of mferrari_lib breeds them too.
-- Soldiers set up their own gun, laser and flamethrower turrets.
local SWEEP_TYPES = {
  "unit", "spider-vehicle", "segmented-unit", "unit-spawner", "turret", "ammo-turret", "electric-turret", "fluid-turret",
}
local SWEEP_PREFIXES = {
  "biterzilla", "bm-motherbiterzilla", "maf-giant-", "bm_fake_human", "bm-spidertron_", "maf_flying_saucer_",
  "maf-behemoth-worm-turret", "maf-colossal-worm-turret", "bm-worm-boss-acid-shooter", "maf-worm-boss-fire-shooter",
  "bm-volcano", "bm-spawner", "mf-gleba-spawner",
}

---@type string[]?
local sweep_names

---@return string[]
function M.sweep_names()
  if not sweep_names then
    sweep_names = {}
    for name in pairs(prototypes.get_entity_filtered({ { filter = "type", type = SWEEP_TYPES } })) do
      local demolisher = name:sub(1, 3) == "mf_" and name:sub(-11) == "-demolisher"
      for _, prefix in ipairs(SWEEP_PREFIXES) do
        if demolisher or name:sub(1, #prefix) == prefix then
          sweep_names[#sweep_names + 1] = name
          break
        end
      end
    end
    table.sort(sweep_names)
  end
  return sweep_names
end

---Removes Big Monsters' monsters of these prototypes from every surface where it may not make them (Nexus keeps its
---own: the bosses of the beacons and its worms).
---@param names string[]
---@return integer removed
function M.sweep(names)
  local removed = 0
  if #names == 0 then
    return removed
  end
  for _, surface in pairs(game.surfaces) do
    local name = surface.name
    if name ~= cfg.PLANET and not M.allowed_surface(name) then
      local found = surface.find_entities_filtered({ force = "enemy", name = names })
      if #found > 0 then
        for _, entity in ipairs(found) do
          entity.destroy()
        end
        removed = removed + #found
        log("nexus-bosses: removed " .. #found .. " monsters of Big Monsters from " .. name
          .. ", which is not in the list of its random events")
        game.print({ "nexus-bosses.msg-big-monsters-removed", #found,
          surface.planet and ("[planet=" .. name .. "]") or name }, { color = util.COLORS.info })
      end
    end
  end
  return removed
end

---Every second: the enemy force counts its entities of each prototype at no cost, so only the prototypes whose count
---has grown are looked for on the surfaces (looking for all of them costs about 60 ms on a large Nauvis).
function M.on_second()
  local counts = storage.bm_counts or {}
  storage.bm_counts = counts
  local enemy = game.forces.enemy
  local grown = {}
  for _, name in ipairs(M.sweep_names()) do
    local count = enemy.get_entity_count(name)
    if count > (counts[name] or 0) then
      grown[#grown + 1] = name
    end
    counts[name] = count
  end
  if M.sweep(grown) > 0 then
    for _, name in ipairs(grown) do
      counts[name] = enemy.get_entity_count(name)
    end
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
