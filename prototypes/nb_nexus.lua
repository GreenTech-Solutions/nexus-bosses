-- Nexus without ordinary enemies, and the way to the Oort cloud behind the trials.
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

-- 2. The warp drive (Oort cloud, Sol) waits for the end of the trials, unless the startup setting
--    "nexus-bosses-gate-warp-drive" is off. Without razi-protocol the warp drive of Nexus opens more than the way to
--    the Oort cloud (the shattered planet and promethium hang behind it as well), so the trials gate that too.
local gate = settings.startup["nexus-bosses-gate-warp-drive"].value
local warp_drive = data.raw.technology and data.raw.technology["warp-drive-engine"]
if not gate then
  log("[nexus-bosses] the trials gate nothing (setting nexus-bosses-gate-warp-drive is off)")
elseif warp_drive then
  warp_drive.prerequisites = warp_drive.prerequisites or {}
  local present = false
  for _, prerequisite in ipairs(warp_drive.prerequisites) do
    if prerequisite == cfg.COMPLETE_TECH then
      present = true
      break
    end
  end
  if not present then
    table.insert(warp_drive.prerequisites, cfg.COMPLETE_TECH)
  end
else
  log("[nexus-bosses] the technology warp-drive-engine does not exist: the trials do not gate anything")
end
