-- Big Monsters supplies prototype sources for boss copies. This module applies the default-off map setting for its
-- random events, always excludes Nexus, and removes its monsters from surfaces outside the allowed planet list.

local cfg = require("lib.nb_data")
local util = require("scripts.nb_util")

local M = {}

local INTERFACE = "bigmonster"

---A call into the other mod: an error there must not stop this one, and goes to the log.
---@return boolean ok
---@return any result_or_error
local function call(function_name, ...)
  local ok, result = pcall(remote.call, INTERFACE, function_name, ...)
  if not ok then
    log("[nexus-bosses] " .. INTERFACE .. "." .. function_name .. ": " .. tostring(result))
  end
  return ok, result
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

return M
