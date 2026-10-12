-- The planet: enemy evolution pinned on the Nexus surface, the enemies of an older game removed, and Big Monsters'
-- list of surfaces.

local cfg = require("lib.nb_data")
local util = require("scripts.nb_util")
local bm = require("scripts.nb_bm")

local M = {}

---Kills and pollution would move the evolution of Nexus; Big Monsters picks its bosses from it.
function M.refresh_evolution()
  local surface = util.nexus()
  local enemy = game.forces.enemy
  if surface and math.abs(enemy.get_evolution_factor(surface) - cfg.EVOLUTION) > 1e-6 then
    enemy.set_evolution_factor(cfg.EVOLUTION, surface)
  end
end

---A game that had Nexus before this mod: the nests and worms the map generator put there would breed at the
---evolution of the trials. On a new map there are none (prototypes/nb_nexus.lua).
local function clear_old_enemies()
  local surface = util.nexus()
  if not surface then
    return
  end
  local removed = 0
  for _, entity in pairs(surface.find_entities_filtered({
    force = "enemy", type = { "unit-spawner", "turret", "unit", "spider-unit", "segmented-unit" },
  })) do
    entity.destroy()
    removed = removed + 1
  end
  if removed > 0 then
    game.print({ "nexus-bosses.msg-old-enemies-removed", removed }, { color = util.COLORS.info })
  end
end

function M.on_init()
  bm.apply_planets_setting()
  clear_old_enemies()
  M.refresh_evolution()
end

function M.on_configuration_changed()
  bm.apply_planets_setting()
  M.refresh_evolution()
end

---@param event EventData.on_runtime_mod_setting_changed
function M.on_settings_changed(event)
  -- Big Monsters handles the event first (a dependency) and resets its list of planets
  if event.setting == "nexus-bosses-big-monsters-beacons-only" or event.setting:sub(1, 3) == "bm-" then
    bm.apply_planets_setting()
  end
end

---@param surface_index integer
function M.on_surface_created(surface_index)
  local surface = game.get_surface(surface_index) --[[@as LuaSurface]]
  if surface.name == cfg.PLANET then
    M.refresh_evolution()
  end
  bm.on_surface_created(surface)
end

---@param tick integer
function M.on_second(tick)
  if tick % cfg.EVOLUTION_REFRESH_TICKS == 0 then
    M.refresh_evolution()
  end
end

return M
