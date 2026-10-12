-- Nexus without ordinary enemies, and the routes of the warp drive behind the trials.
-- Runs in data-final-fixes after razi-protocol (optional dependency), which is the mod that puts the nests there.

local cfg = require("lib.nb_data")

-- 1. No ordinary enemies. The enemies of the planet do not come from the entries of its entity autoplace list: they
--    are placed by the autoplace controls of the planet (enemy-base, frost_enemy_base, hot_enemy_base, electric_enemies
--    with razi-protocol, all at 1/1/1) for every enemy prototype that has an autoplace, and an entity that the list
--    does not mention is placed too (AutoplaceSpecification::default_enabled is true for all of them). razi-protocol's
--    31 entries there are 25 empty ones ({}) and 6 zero overrides {frequency = 0, size = 0, richness = 0} that keep
--    the vanilla biter and spitter spawners and small to behemoth worms away. Deleting the entries would therefore
--    bring those six vanilla prototypes back (measured on fresh maps: 84-95 vanilla nests in the first 16 chunks).
--    The way to switch an enemy off is the zero override, which takes priority over the control of the planet:
--    a. every entity prototype whose autoplace places the enemy force gets a zero override in the entity list
--       (spawners, worms, the centipedes of Tenebris);
--    b. every autoplace control of the planet that is in the category "enemy" is set to zero, which also covers the
--       enemies of a mod that loads after this one.
local planet = data.raw.planet and data.raw.planet[cfg.PLANET]
local map_gen = planet and planet.map_gen_settings
local autoplace = map_gen and map_gen.autoplace_settings
local entity_settings = autoplace and autoplace.entity and autoplace.entity.settings
if entity_settings then
  local prototype_count = 0
  for type_name in pairs(defines.prototypes.entity) do
    for name, prototype in pairs(data.raw[type_name] or {}) do
      local spec = prototype.autoplace
      if type(spec) == "table" and spec.force == "enemy" then
        entity_settings[name] = { frequency = 0, size = 0, richness = 0 }
        prototype_count = prototype_count + 1
      end
    end
  end
  log("[nexus-bosses] " .. cfg.PLANET .. ": zero override for " .. prototype_count .. " enemy prototypes with an autoplace")
else
  log("[nexus-bosses] the planet " .. cfg.PLANET .. " has no entity autoplace settings: no enemy prototype zeroed")
end

local controls = map_gen and map_gen.autoplace_controls
if controls then
  local control_count = 0
  local control_prototypes = data.raw["autoplace-control"] or {}
  for name in pairs(controls) do
    local control = control_prototypes[name]
    if control and control.category == "enemy" then
      controls[name] = { frequency = 0, size = 0, richness = 0 }
      control_count = control_count + 1
    end
  end
  log("[nexus-bosses] " .. cfg.PLANET .. ": " .. control_count .. " enemy autoplace controls set to zero")
else
  log("[nexus-bosses] the planet " .. cfg.PLANET .. " has no autoplace controls: no enemy control zeroed")
end

-- 2. The routes of the warp drive (Oort cloud, Sol; without razi-protocol also the shattered planet and the edge of the
--    system) move to the technology that the warp key researches (prototypes/nb_technologies.lua), unless the startup
--    setting "nexus-bosses-gate-warp-drive" is off. The warp drive itself is researched as before: without the key it
--    has nowhere to go. The module returns the moved effects.
local routes = {}
local warp_drive = data.raw.technology["warp-drive-engine"]
if not settings.startup["nexus-bosses-gate-warp-drive"].value then
  log("[nexus-bosses] the trials gate nothing (setting nexus-bosses-gate-warp-drive is off)")
elseif warp_drive then
  local kept = {}
  for _, effect in ipairs(warp_drive.effects or {}) do
    if effect.type == "unlock-space-location" then
      routes[#routes + 1] = effect
    else
      kept[#kept + 1] = effect
    end
  end
  warp_drive.effects = kept
  log("[nexus-bosses] " .. #routes .. " routes of warp-drive-engine move to " .. cfg.SILENCE_TECH)
else
  log("[nexus-bosses] the technology warp-drive-engine does not exist: the trials gate nothing")
end

return { routes = routes }
