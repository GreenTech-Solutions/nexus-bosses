-- The planet: enemy evolution pinned at 0.99 on the Nexus surface, and Big-Monsters kept off the planets.

local cfg = require("lib.nb_data")
local util = require("scripts.nb_util")
local bm = require("scripts.nb_bm")

local M = {}

---Enemy evolution on Nexus is fixed. Big-Monsters reads it to choose the strongest variants of its bosses and
---the spawner of the Toxic Lair to choose the tiers of its guards; kills and pollution would otherwise move it.
function M.refresh_evolution()
  local surface = util.nexus()
  local enemy = game.forces.enemy
  if not (surface and enemy and enemy.valid) then
    return
  end
  if math.abs(enemy.get_evolution_factor(surface) - cfg.EVOLUTION) > 1e-6 then
    enemy.set_evolution_factor(cfg.EVOLUTION, surface)
  end
end

---The refresh, protected: a failure here is logged, it must not stop the game every minute.
local function refresh_safely()
  local ok, err = pcall(M.refresh_evolution)
  if not ok then
    log("[nexus-bosses] cannot set the evolution on Nexus: " .. tostring(err))
  end
end

---A game that had Nexus before this mod: the nests, worms and biters of the enemy force that the map generator put on
---Nexus would breed at the evolution of the trials (0.99). This mod keeps Nexus free of them on a new map
---(prototypes/nb_nexus.lua), so the ones that are there are removed when the mod is added.
local function clear_old_enemies()
  local surface = util.nexus()
  local enemy = game.forces.enemy
  if not (surface and enemy and enemy.valid) then
    return
  end
  local removed = 0
  for _, entity in pairs(surface.find_entities_filtered({
    force = enemy, type = { "unit-spawner", "turret", "unit", "spider-unit", "segmented-unit" },
  })) do
    if entity.valid then
      entity.destroy()
      removed = removed + 1
    end
  end
  if removed > 0 then
    game.print({ "nexus-bosses.msg-old-enemies-removed", removed }, { color = util.COLORS.info })
    log("[nexus-bosses] removed " .. removed .. " enemy entities that were on Nexus before the mod")
  end
end

function M.on_init()
  bm.disable_planets()
  local ok, err = pcall(clear_old_enemies)
  if not ok then
    log("[nexus-bosses] cannot clear the old enemies of Nexus: " .. tostring(err))
  end
  refresh_safely()
end

function M.on_configuration_changed()
  bm.disable_planets()
  refresh_safely()
end

---Big-Monsters resets its list of planets whenever any runtime setting changes. Its handler for the event runs
---before this one (Big-Monsters is a dependency), so the list is emptied again.
function M.on_settings_changed()
  bm.disable_planets()
end

---@param surface_index integer
function M.on_surface_created(surface_index)
  local surface = game.get_surface(surface_index)
  if surface and surface.name == cfg.PLANET then
    refresh_safely()
  end
end

---Once a minute.
---@param tick integer
function M.on_second(tick)
  if tick % cfg.EVOLUTION_REFRESH_TICKS == 0 then
    refresh_safely()
  end
end

return M
