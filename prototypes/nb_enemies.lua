-- Bosses copied from the prototypes of other mods. The startup setting "nexus-bosses-boss-health" scales their
-- maximum health along with the other bosses.

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

-- Arachnid Queen and her nests. Their health is set by cfg.QUEEN_HEALTH and cfg.NEST_HEALTH. The nest is an arachnid
-- spawner that breeds warriors and spitters only and keeps four of them at its side.
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
maw_fire.max_health = maw_fire.max_health * cfg.MAW_FIRE_HEALTH_SHARE * HEALTH
local maw_acid = copy("turret", "bm-worm-boss-acid-shooter", cfg.MAW_ACID)
maw_acid.max_health = maw_acid.max_health * cfg.MAW_ACID_HEALTH_SHARE * HEALTH

-- Last Commander: Big Monsters supplies the unit prototype; this mod spawns and controls the copy.
local commander = copy("unit", "bm_fake_human_ultimate_boss_cannon_20", cfg.COMMANDER)
commander.max_health = cfg.COMMANDER_HEALTH * HEALTH

-- The six Colossus variants are copies of Big Monsters' level 5 units. Keep the original prototypes untouched:
-- Big Monsters only supplies the source prototypes; Nexus Bosses spawns and controls these copies.
local colossus_variants = {}
for _, variant in ipairs(cfg.COLOSSUS_VARIANTS) do
  local original = data.raw.unit[variant.original]
  if not original then
    error("nexus-bosses: " .. variant.original .. " of Big Monsters is missing")
  end
  local original_health = original.max_health
  if type(original_health) ~= "number" then
    error("nexus-bosses: " .. variant.original .. " of Big Monsters has no max_health")
  end
  local colossus = copy("unit", variant.original, cfg.COLOSSUS_PREFIX .. variant.id)
  colossus.max_health = original_health * variant.health_share * HEALTH
  colossus_variants[#colossus_variants + 1] = colossus
end

-- Plague Hulk: the crashed ship of Toxic_biters. Its spawner picks boss biters by evolution; at most 7 at its side.
local hulk = copy("unit-spawner", "tb_infected_ship_boss", cfg.HULK)
hulk.max_health = cfg.HULK_HEALTH * HEALTH / SPAWNER_GROWTH
hulk.max_count_of_owned_units = 7
hulk.max_friends_around_to_spawn = 5

-- Storm Guardian: walks in the storms it feeds on, so lightning must not hurt it.
local guardian = copy("unit", "walking-electric-unit-boss-10", cfg.GUARDIAN)
guardian.max_health = cfg.GUARDIAN_HEALTH * HEALTH
immune_to(guardian, "electric")

-- Watcher and Rogue Spidertron keep the behavior and visuals of their source prototypes, with their own health.
local watcher = copy("spider-vehicle", "maf_flying_saucer_8", cfg.WATCHER)
watcher.max_health = cfg.WATCHER_HEALTH * HEALTH
local spidertron = copy("spider-vehicle", "bm-spidertron_5", cfg.SPIDERTRON)
spidertron.max_health = cfg.SPIDERTRON_HEALTH * HEALTH

data:extend({ queen, nest, maw_fire, maw_acid, commander, hulk, guardian, watcher, spidertron })
data:extend(colossus_variants)

-- Devourer: a big demolisher whose health is set by cfg.DEVOURER_HEALTH. Every segment prototype has the health of the
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
