-- The bosses the mod spawns itself, copied from the prototypes of other mods. The startup setting
-- "nexus-bosses-boss-health" scales their health; the bosses of Big Monsters are scaled when they appear.

local util = require("util")
local cfg = require("lib.nb_data")

local HEALTH = settings.startup["nexus-bosses-boss-health"].value --[[@as number]]

-- The game multiplies the health of a spawner by spawner_evolution_factor_health_modifier ^ evolution (10 in vanilla;
-- 2.0.7: "Biter spawner health grows with evolution, up to 10 times"). Nexus is pinned at cfg.EVOLUTION.
local SPAWNER_GROWTH = data.raw["utility-constants"].default.spawner_evolution_factor_health_modifier
  ^ cfg.EVOLUTION

---A copy of a prototype under the mod's name. Never placed by the map generator, never minable.
---@param type_name string
---@param original string
---@param name string
---@return table
local function copy(type_name, original, name)
  local prototype = util.table.deepcopy(data.raw[type_name][original]) --[[@as table]]
  prototype.name = name
  prototype.localised_name = { "entity-name." .. name }
  prototype.localised_description = { "entity-description." .. name }
  prototype.autoplace = nil
  prototype.minable = nil
  prototype.order = (prototype.order or "z") .. "-nexus"
  return prototype
end

---@param prototype table
---@param damage_type string
local function immune_to(prototype, damage_type)
  prototype.resistances = prototype.resistances or {}
  for _, resistance in ipairs(prototype.resistances) do
    if resistance.type == damage_type then
      resistance.percent = 100
      resistance.decrease = 0
      return
    end
  end
  table.insert(prototype.resistances, { type = damage_type, percent = 100 })
end

-- Arachnid Queen and her nests. The nest is an arachnid spawner that breeds warriors and spitters only (at the
-- evolution of Nexus the original would breed leviathans of 80 000 health) and keeps four of them at its side.
local queen = copy("unit", "maf-boss-arachnid-biter-10", cfg.QUEEN)
queen.max_health = cfg.QUEEN_HEALTH * HEALTH

local nest = copy("unit-spawner", "arachnid-spawner-unitspawner", cfg.QUEEN_NEST)
nest.max_health = cfg.NEST_HEALTH * HEALTH / SPAWNER_GROWTH
nest.max_count_of_owned_units = 4
nest.max_friends_around_to_spawn = 4
nest.result_units = {
  { unit = "arachnid-biter-warrior-unit", spawn_points = { { evolution_factor = 0, spawn_weight = 2 } } },
  { unit = "arachnid-spitter-bigspitter-unit", spawn_points = { { evolution_factor = 0, spawn_weight = 1 } } },
}

-- Twin Maws: the two boss worms of Big Monsters.
local maw_fire = copy("turret", "maf-worm-boss-fire-shooter", cfg.MAW_FIRE)
maw_fire.max_health = maw_fire.max_health * HEALTH
local maw_acid = copy("turret", "bm-worm-boss-acid-shooter", cfg.MAW_ACID)
maw_acid.max_health = maw_acid.max_health * HEALTH

-- Plague Hulk: the crashed ship of Toxic_biters. Its spawner picks boss biters by evolution; at most 7 at its side.
local hulk = copy("unit-spawner", "tb_infected_ship_boss", cfg.HULK)
hulk.max_health = cfg.HULK_HEALTH * HEALTH / SPAWNER_GROWTH
hulk.max_count_of_owned_units = 7
hulk.max_friends_around_to_spawn = 5

-- Storm Guardian: walks in the storms it feeds on, so lightning must not hurt it.
local guardian = copy("unit", "walking-electric-unit-boss-10", cfg.GUARDIAN)
guardian.max_health = cfg.GUARDIAN_HEALTH * HEALTH
immune_to(guardian, "electric")

data:extend({ queen, nest, maw_fire, maw_acid, hulk, guardian })

-- Devourer: a big demolisher with 5 million health. Every segment prototype of a demolisher has the health of the
-- head, so the segments are copied too; they carry the Devourer's name in the tooltip of the body.
local devourer = copy("segmented-unit", "big-demolisher", cfg.DEVOURER)
devourer.max_health = cfg.DEVOURER_HEALTH * HEALTH
devourer.healing_per_tick = cfg.DEVOURER_HEALING_PER_TICK * HEALTH
devourer.factoriopedia_simulation = nil -- the original one creates a big-demolisher

local segments = {}
local converted = {} -- the list may repeat one table: convert each table once
for _, entry in ipairs(devourer.segment_engine.segments) do
  if not converted[entry] then
    converted[entry] = true
    local name = cfg.DEVOURER .. "-" .. entry.segment
    if not segments[name] then
      local original = data.raw["segment"][entry.segment]
      local segment = util.table.deepcopy(original)
      segment.name = name
      segment.max_health = devourer.max_health
      -- "<Big demolisher> segment" -> "<Devourer> segment"
      local key = type(original.localised_name) == "table" and original.localised_name[1] or "entity-name.demolisher-segment"
      segment.localised_name = { key, { "entity-name." .. cfg.DEVOURER } }
      segments[name] = segment
    end
    entry.segment = name
  end
end
for _, segment in pairs(segments) do
  data:extend({ segment })
end
data:extend({ devourer })
