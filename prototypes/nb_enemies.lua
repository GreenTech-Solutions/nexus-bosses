-- The bosses that the mod spawns itself, copied from the prototypes of other mods (data-final-fixes, so the
-- copies see what razi-protocol and the others have done to the originals):
--   nexus-toxic-lair    <- tb_infected_ship_boss (Toxic_biters), 2 000 000 health on Nexus
--   nexus-host-worm     <- big-demolisher (Space Age), 5 000 000 health, the same resistances, 3 000 health/s
--                          regeneration, segments copied with it
--   nexus-storm-guardian <- walking-electric-unit-boss-10, when the original is not immune to electricity or the health
--                          is scaled
--   nexus-arachnid-queen <- maf-boss-arachnid-biter-10, only when the health is scaled
-- The startup setting "nexus-bosses-boss-health" scales the health of these four (and the regeneration of the worm with
-- it). The bosses that Big-Monsters creates follow the health settings of Big-Monsters.

local util = require("util")
local cfg = require("lib.nb_data")

local HEALTH = settings.startup["nexus-bosses-boss-health"].value --[[@as number]]
local SCALED = math.abs(HEALTH - 1) > 1e-9

local function has_full_resistance(prototype, damage_type)
  for _, resistance in ipairs(prototype.resistances or {}) do
    if resistance.type == damage_type and (resistance.percent or 0) >= 100 then
      return true
    end
  end
  return false
end

-- The Toxic Lair: the crashed ship of the toxic biters. It keeps the spawner of the original (the units are the
-- boss variants maf-boss-toxic-biter/spitter-1..10, picked by the evolution, which is pinned at 0.99 on Nexus),
-- but at most 7 of them are alive at its side; the guards are placed around it by scripts/nb_spawn.lua.
--
-- Health. The health of a unit spawner grows with the evolution of the surface it is created on: it is multiplied by
-- utility-constants.spawner_evolution_factor_health_modifier (10 in the game) raised to the evolution (Factorio 2.0.7
-- changelog: "Biter spawner health grows with evolution, up to 10 times"). The lair is created on Nexus at 0.99, so the
-- prototype carries 2 000 000 / 10^0.99 and the lair has 2 000 000 there (measured: 2 000 009).
local ship = data.raw["unit-spawner"] and data.raw["unit-spawner"]["tb_infected_ship_boss"]
if ship then
  local constants = data.raw["utility-constants"] and data.raw["utility-constants"].default
  local growth = constants and constants.spawner_evolution_factor_health_modifier or 10
  local lair = util.table.deepcopy(ship)
  lair.name = "nexus-toxic-lair"
  lair.localised_name = { "entity-name.nexus-toxic-lair" }
  lair.localised_description = { "entity-description.nexus-toxic-lair" }
  lair.max_health = cfg.LAIR_HEALTH * HEALTH / growth ^ cfg.EVOLUTION
  lair.max_count_of_owned_units = 7
  lair.max_friends_around_to_spawn = 5
  lair.order = "b-d-b[nexus-toxic-lair]"
  lair.minable = nil
  data:extend({ lair })
else
  log("[nexus-bosses] tb_infected_ship_boss does not exist: no Toxic Lair")
end

-- The Host Worm: a demolisher of the size of a big one with 5 million health. Everything else, the resistances
-- (fire, laser and impact damage do nothing) included, is copied from the big demolisher, except the regeneration:
-- the original heals 400 health per tick (24 000 per second, 8 % of its health), which at 5 million health would be a
-- wall for any base that cannot sustain 24 000 damage per second; the worm heals 50 per tick (3 000 per second).
--
-- The body. Every segment prototype of the original has the health of the head (the same holds for the demolishers of
-- Big-Monsters and the centipedes of Tenebris), so the segments are copied with the health of the worm; the copies
-- also carry the name of the worm instead of the big demolisher's in the tooltip of the body.
local demolisher = data.raw["segmented-unit"] and data.raw["segmented-unit"]["big-demolisher"]
if demolisher then
  local worm = util.table.deepcopy(demolisher)
  worm.name = "nexus-host-worm"
  worm.localised_name = { "entity-name.nexus-host-worm" }
  worm.localised_description = { "entity-description.nexus-host-worm" }
  worm.max_health = cfg.WORM_HEALTH * HEALTH
  worm.healing_per_tick = cfg.WORM_HEALING_PER_TICK * HEALTH
  worm.order = "s-j[nexus-host-worm]"
  worm.factoriopedia_simulation = nil -- the original one creates a big-demolisher

  local originals = data.raw["segment"] or {}
  local copies = {}
  local copied = {}
  local converted = {} -- the entries of the list may be one table repeated: convert each table once
  local segments = worm.segment_engine and worm.segment_engine.segments or {}
  for _, entry in ipairs(segments) do
    if not converted[entry] then
      converted[entry] = true
      local original = originals[entry.segment]
      if original then
        local name = "nexus-host-worm-" .. entry.segment
        if not copied[name] then
          copied[name] = true
          local copy = util.table.deepcopy(original)
          copy.name = name
          copy.max_health = worm.max_health
          -- "<Big demolisher> segment" / "tail" -> "<Host Worm> segment" / "tail"
          local key = "entity-name.demolisher-segment"
          local original_name = original.localised_name
          if type(original_name) == "table" and type(original_name[1]) == "string" then
            key = original_name[1]
          end
          copy.localised_name = { key, { "entity-name.nexus-host-worm" } }
          copies[#copies + 1] = copy
        end
        entry.segment = name
      else
        log("[nexus-bosses] the segment " .. tostring(entry.segment) .. " of big-demolisher does not exist: kept as it is")
      end
    end
  end
  data:extend(copies)
  data:extend({ worm })
else
  log("[nexus-bosses] big-demolisher does not exist: no Host Worm")
end

-- The Storm Guardian must not be hurt by the lightning of the storms it is born for. Electric_flying_enemies'
-- walking-electric-unit-boss-10 has 100 % electric resistance; if some mod takes it away, or the health is scaled, a
-- copy takes over.
local guardian = data.raw.unit and data.raw.unit["walking-electric-unit-boss-10"]
if guardian and (SCALED or not has_full_resistance(guardian, "electric")) then
  local copy = util.table.deepcopy(guardian)
  copy.name = "nexus-storm-guardian"
  copy.localised_name = { "entity-name.nexus-storm-guardian" }
  copy.localised_description = { "entity-description.nexus-storm-guardian" }
  copy.order = (guardian.order or "f-f-wboss") .. "-nexus"
  copy.max_health = (guardian.max_health or 10) * HEALTH
  copy.resistances = copy.resistances or {}
  local patched = false
  for _, resistance in ipairs(copy.resistances) do
    if resistance.type == "electric" then
      resistance.percent = 100
      resistance.decrease = 0
      patched = true
    end
  end
  if not patched then
    table.insert(copy.resistances, { type = "electric", percent = 100 })
  end
  data:extend({ copy })
  log("[nexus-bosses] using nexus-storm-guardian (health x" .. HEALTH .. ", immune to electricity)")
end

-- The Arachnid Queen of Arachnids_enemy, as it is unless the health is scaled.
local queen = data.raw.unit and data.raw.unit["maf-boss-arachnid-biter-10"]
if queen and SCALED then
  local copy = util.table.deepcopy(queen)
  copy.name = "nexus-arachnid-queen"
  copy.localised_name = { "entity-name.nexus-arachnid-queen" }
  copy.localised_description = queen.localised_description
  copy.order = (queen.order or "b-b-a") .. "-nexus"
  copy.max_health = (queen.max_health or 10) * HEALTH
  data:extend({ copy })
  log("[nexus-bosses] using nexus-arachnid-queen (health x" .. HEALTH .. ")")
end
