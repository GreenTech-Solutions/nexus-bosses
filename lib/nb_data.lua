-- Constants shared by the data stage and the control stage. Pure Lua: no game API.

---@class NbCircle a stage of the signal of Nexus
---@field stage string "whisper", "chorus" or "convergence": its name in the locale (nexus-bosses.stage-<stage>)
---@field tech string unlocks the beacons of the stage
---@field reward string|nil researched by the script when the three bosses of the circle are beaten
---@field bosses string[]
---@field alloy integer omega alloy per beacon
---@field processors integer advanced photon processors per beacon
---@field seconds number crafting time of a beacon
---@field precursors integer units in each precursor wave

---@class NbBmSet
---@field event string event of the remote interface "bigmonster"
---@field types string[] entity types of the bosses the event creates
---@field prefixes string[] name prefixes of those bosses
---@field explore_chunks integer chunk radius around the spawn of the force that the event walks through

---@class NbBossSpec
---@field kind "own"|"bm" "own": scripts/bosses/<id>.lua spawns it, "bm": the Big Monsters event does
---@field entity string the entity whose icon marks the beacon, the trophy and the technologies
---@field precursors string[] units of the precursor waves
---@field bm NbBmSet|nil
---@field circle integer
---@field slot integer

local M = {}

M.PLANET = "nexus"
M.PLANET_TECH = "planet-discovery-nexus"

-- Pinned on the Nexus surface: Big Monsters picks the tier of its bosses from it, and below 0.9 it makes no bosses.
M.EVOLUTION = 0.99
M.EVOLUTION_REFRESH_TICKS = 60 * 60

-- Lightning chance multiplier once the Storm Guardian is dead (remote interface "nexus-threat").
M.STORM_MULTIPLIER = 0.5

M.BEACON_PREFIX = "nexus-summon-"
M.TROPHY_PREFIX = "nexus-trophy-"
M.WARP_KEY = "nexus-warp-key"
-- Researched by crafting the warp key; takes over the routes (unlock-space-location) of the warp drive.
M.SILENCE_TECH = "nexus-silence"

M.ALLOY_ITEM = "omega-alloy"
M.PROCESSOR_ITEM = "advanced-photon-processor"

---@type NbCircle[]
M.CIRCLES = {
  {
    stage = "whisper",
    tech = "nexus-whisper",
    reward = "nexus-chorus",
    bosses = { "arachnid-queen", "watcher", "rogue-spidertron" },
    alloy = 50,
    processors = 2,
    seconds = 30,
    precursors = 6,
  },
  {
    stage = "chorus",
    tech = "nexus-chorus",
    reward = "nexus-convergence",
    bosses = { "twin-maws", "colossus", "plague-hulk" },
    alloy = 75,
    processors = 3,
    seconds = 60,
    precursors = 10,
  },
  {
    stage = "convergence",
    tech = "nexus-convergence",
    reward = nil, -- the end is the warp key, crafted from the nine trophies
    bosses = { "storm-guardian", "devourer", "last-commander" },
    alloy = 110,
    processors = 5,
    seconds = 120,
    precursors = 14,
  },
}

-- The bosses the mod spawns itself are copies made in prototypes/nb_enemies.lua.
M.QUEEN = "nexus-arachnid-queen"
M.QUEEN_NEST = "nexus-queen-nest"
M.MAW_FIRE = "nexus-maw-fire"
M.MAW_ACID = "nexus-maw-acid"
M.HULK = "nexus-plague-hulk"
M.GUARDIAN = "nexus-storm-guardian"
M.DEVOURER = "nexus-devourer"

-- Health before the startup setting "nexus-bosses-boss-health". The hulk is a spawner, whose health the game
-- multiplies by 10^evolution: the prototype gets HULK_HEALTH / 10^0.99.
M.QUEEN_HEALTH = 500000
M.NEST_HEALTH = 25000
M.HULK_HEALTH = 2000000
M.GUARDIAN_HEALTH = 3000000
M.DEVOURER_HEALTH = 5000000
M.DEVOURER_HEALING_PER_TICK = 50 -- the big demolisher heals 400 a tick, 8 % of its health every second

local BM_COLOSSUS_PREFIXES = {
  -- with a soldier chance above 0 the event may pick a human boss, flamethrowers without "boss" in the name
  "biterzilla", "maf-giant-", "bm-motherbiterzilla", "bm_fake_human_boss_", "bm_fake_human_flamethrower_",
}

local SPECS = {
  ["arachnid-queen"] = {
    kind = "own",
    entity = "maf-boss-arachnid-biter-10",
    precursors = { "arachnid-biter-warrior-unit", "arachnid-spitter-bigspitter-unit" },
  },
  ["watcher"] = {
    kind = "bm",
    entity = "maf_flying_saucer_8",
    precursors = { "flying-electric-unit-3" },
    bm = { event = "flying_saucer", types = { "spider-vehicle" }, prefixes = { "maf_flying_saucer_" }, explore_chunks = 16 },
  },
  ["rogue-spidertron"] = {
    kind = "bm",
    entity = "bm-spidertron_5",
    precursors = { "arachnid-biter-tiger-unit" },
    bm = { event = "spidertron", types = { "spider-vehicle" }, prefixes = { "bm-spidertron_" }, explore_chunks = 16 },
  },
  ["twin-maws"] = {
    kind = "own",
    entity = "maf-worm-boss-fire-shooter",
    precursors = { "behemoth-spitter" },
  },
  ["colossus"] = {
    kind = "bm",
    entity = "biterzilla15",
    precursors = { "behemoth-biter" },
    bm = { event = "biterzilla", types = { "unit" }, prefixes = BM_COLOSSUS_PREFIXES, explore_chunks = 16 },
  },
  ["plague-hulk"] = {
    kind = "own",
    entity = "tb_infected_ship_boss",
    precursors = { "big-toxic-biter" },
  },
  ["storm-guardian"] = {
    kind = "own",
    entity = "walking-electric-unit-boss-10",
    precursors = { "walking-electric-unit-3", "flying-electric-unit-3" },
  },
  ["devourer"] = {
    kind = "own",
    entity = "big-demolisher",
    precursors = { "behemoth-biter" },
  },
  ["last-commander"] = {
    kind = "bm",
    entity = "bm_fake_human_ultimate_boss_cannon_20",
    precursors = { "bm_fake_human_machine_gunner_5" },
    bm = {
      event = "ultimate_boss", types = { "unit" }, prefixes = { "bm_fake_human_ultimate_boss_" }, explore_chunks = 24,
    },
  },
}

---@type string[] boss ids in the order of the circles
M.ORDER = {}
---@type table<string, NbBossSpec>
M.BOSSES = {}
for circle_index, circle in ipairs(M.CIRCLES) do
  for slot, id in ipairs(circle.bosses) do
    local spec = assert(SPECS[id], id)
    M.ORDER[#M.ORDER + 1] = id
    M.BOSSES[id] = {
      kind = spec.kind,
      entity = spec.entity,
      precursors = spec.precursors,
      bm = spec.bm,
      circle = circle_index,
      slot = slot,
    }
  end
end

-- Prototypes of other mods the mod is made of. data-final-fixes.lua stops the load when one is missing: a renamed
-- prototype should break the game at start, not in the middle of a trial.
M.REQUIRED = {
  { "unit", "maf-boss-arachnid-biter-10", "Arachnids_enemy" },
  { "unit", "arachnid-biter-leviathan-unit", "Arachnids_enemy" },
  { "unit-spawner", "arachnid-spawner-unitspawner", "Arachnids_enemy" },
  { "unit", "arachnid-biter-warrior-unit", "Arachnids_enemy" },
  { "unit", "arachnid-spitter-bigspitter-unit", "Arachnids_enemy" },
  { "unit", "arachnid-biter-tiger-unit", "Arachnids_enemy" },
  { "unit-spawner", "tb_infected_ship_boss", "Toxic_biters" },
  { "unit", "big-toxic-biter", "Toxic_biters" },
  { "unit", "walking-electric-unit-boss-10", "Electric_flying_enemies" },
  { "unit", "walking-electric-unit-5", "Electric_flying_enemies" },
  { "unit", "flying-electric-unit-5", "Electric_flying_enemies" },
  { "unit", "walking-electric-unit-3", "Electric_flying_enemies" },
  { "unit", "flying-electric-unit-3", "Electric_flying_enemies" },
  { "turret", "maf-worm-boss-fire-shooter", "Big-Monsters" },
  { "turret", "bm-worm-boss-acid-shooter", "Big-Monsters" },
  { "spider-vehicle", "maf_flying_saucer_8", "Big-Monsters" },
  { "spider-vehicle", "bm-spidertron_5", "Big-Monsters" },
  { "unit", "biterzilla15", "Big-Monsters" },
  { "unit", "bm_fake_human_ultimate_boss_cannon_20", "Big-Monsters" },
  { "unit", "bm_fake_human_machine_gunner_5", "Big-Monsters" },
  { "segmented-unit", "big-demolisher", "space-age" },
  { "planet", "nexus", "Nexus" },
}

---@param id string
---@return string
function M.beacon_name(id)
  return M.BEACON_PREFIX .. id
end

---@param id string
---@return string
function M.trophy_name(id)
  return M.TROPHY_PREFIX .. id
end

---@param name string entity or item name
---@return string|nil boss id when the name is a beacon
function M.boss_of_beacon(name)
  if name:sub(1, #M.BEACON_PREFIX) ~= M.BEACON_PREFIX then
    return nil
  end
  local id = name:sub(#M.BEACON_PREFIX + 1)
  return M.BOSSES[id] and id or nil
end

return M
