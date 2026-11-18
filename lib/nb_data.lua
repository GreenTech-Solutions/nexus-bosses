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
---@field color Color the antenna of its beacons, its bearings and its summon circle

---@class NbBossSpec
---@field entity string the entity whose icon marks the beacon, the trophy and the technologies
---@field precursors string[] units of the precursor waves
---@field circle integer
---@field slot integer

local M = {}

M.PLANET = "nexus"
M.PLANET_TECH = "planet-discovery-nexus"

-- Enemy evolution is pinned on the Nexus surface; some spawner prototypes scale their health with it.
M.EVOLUTION = 0.99
M.EVOLUTION_REFRESH_TICKS = 60 * 60

-- Lightning chance multiplier once the Storm Guardian is dead (remote interface "nexus-threat").
M.STORM_MULTIPLIER = 0.5

M.BEACON_PREFIX = "nexus-summon-"
M.TROPHY_PREFIX = "nexus-trophy-"
M.WARP_KEY = "nexus-warp-key"
-- Researched by crafting the warp key; takes over the routes (unlock-space-location) of the warp drive.
M.SILENCE_TECH = "nexus-silence"

-- The expedition: a wreck with a log for every boss, on a ring around the spawn of the force, one ring a stage
M.WRECK_PREFIX = "nexus-expedition-wreck-"
M.WRECK_VARIANTS = 3
M.EXPEDITION_RINGS = { { 100, 250 }, { 250, 450 }, { 450, 700 } }
-- The story of the expedition: its camp, where the first log lies (opens with the Whisper), and the last stand of
-- its commander, the epilogue (opens with Silence)
M.CAMP = "nexus-expedition-camp"
M.CAMP_RING = { 100, 150 }
M.LAST_STAND = "nexus-expedition-last-stand"
M.LAST_STAND_RING = { 1150, 1250 }
M.BADGE = "nexus-bosses-commander-badge"

-- The vault of the builders: a glyph lock at a vault ruin of Fulgora on Nexus, opened after Silence; a hatch leads
-- down to a surface of its own with a few dark halls, and the last one holds the treasure
M.VAULT_RUIN = "fulgoran-ruin-vault"
M.VAULT_RING = { 250, 1000 }
M.GLYPHS = 8
M.GLYPH_PREFIX = "nexus-bosses-glyph-"
M.CODE_LENGTH = 4
M.OBELISK = "nexus-bosses-obelisk"
M.CONSOLE = "nexus-bosses-glyph-console"
M.HATCH = "nexus-bosses-vault-hatch"
M.STAIRS = "nexus-bosses-vault-stairs"
M.RELIQUARY = "nexus-bosses-reliquary"
M.RELIC = "nexus-bosses-builders-relic"
M.ECHO_TECH = "nexus-builders-echo"
M.VAULT_SURFACE = "nexus-bosses-vault"
M.VAULT_TRACK = "nexus-bosses-vault"
M.SHORTCUT_DETECTOR = "nexus-bosses-detector"
M.SHORTCUT_CODEX = "nexus-bosses-codex"

-- Bearings: direction finders point at the lair of a boss; a beacon lit in it gives more at the victory
M.BEARING_TECH = "nexus-signal-bearing"
M.FINDER = "nexus-bosses-direction-finder"
M.LAIR_RINGS = { { 250, 450 }, { 450, 700 }, { 700, 1000 } }
M.LAIR_RADIUS = 30
M.LAIR_REMAINS_PREFIX = "nexus-bosses-lair-remains-"
M.LAIR_SCORCH = "nexus-bosses-lair-scorchmark"
-- the second trophy of a fight in the lair: one step better with every such fight
M.LAIR_QUALITIES = { "uncommon", "rare", "epic", "legendary" }
M.LAIR_LOOT_SHARE = 0.5 -- of the beacon recipe
-- Pylons: a broken pylon of suppression stands in every found lair; a trophy of its boss of a better quality
-- repairs it, and a boss called in that lair comes with less health, by the quality of the trophy
M.PYLON = "nexus-bosses-pylon"
M.PYLON_SHARES = { uncommon = 0.1, rare = 0.2, epic = 0.3, legendary = 0.4 }

-- Storms: a storm of Nexus-Threat wakes the lightning attractor ruins of Nexus; a charged shard from one weakens
-- the Storm Guardian, through the charged beacons
M.RUIN_ATTRACTOR = "fulgoran-ruin-attractor"
M.SHARD = "nexus-bosses-storm-shard"
M.CHARGES = 3
M.CHARGED_BOSS = "storm-guardian"

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
    color = { r = 0.55, g = 0.85, b = 1 }, -- blue
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
    color = { r = 1, g = 0.8, b = 0.35 }, -- amber
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
    color = { r = 1, g = 0.4, b = 0.35 }, -- red
  },
}

-- The bosses the mod spawns itself are copies made in prototypes/nb_enemies.lua.
M.QUEEN = "nexus-arachnid-queen"
M.QUEEN_NEST = "nexus-queen-nest"
M.MAW_FIRE = "nexus-maw-fire"
M.MAW_ACID = "nexus-maw-acid"
M.COMMANDER = "nexus-last-commander"
M.HULK = "nexus-plague-hulk"
M.GUARDIAN = "nexus-storm-guardian"
M.DEVOURER = "nexus-devourer"
M.WATCHER = "nexus-watcher"
M.SPIDERTRON = "nexus-rogue-spidertron"

-- Health before the startup setting "nexus-bosses-boss-health". The hulk is a spawner, whose health the game
-- multiplies by 10^evolution: the prototype gets HULK_HEALTH / 10^0.99.
M.QUEEN_HEALTH = 500000
M.NEST_HEALTH = 25000
M.COMMANDER_HEALTH = 5040000
M.HULK_HEALTH = 2000000
M.GUARDIAN_HEALTH = 3000000
M.DEVOURER_HEALTH = 5000000
M.DEVOURER_HEALING_PER_TICK = 50 -- the big demolisher heals 400 a tick, 8 % of its health every second
M.WATCHER_HEALTH = 56000
M.SPIDERTRON_HEALTH = 26000

-- Colossus copies of Big Monsters' level 5 units, selected when its beacon is lit.
M.COLOSSUS_VARIANTS = {
  { id = "fire", original = "biterzilla15" },
  { id = "storm", original = "biterzilla25" },
  { id = "armored", original = "biterzilla35" },
  { id = "mother", original = "bm-motherbiterzilla5" },
  { id = "fire-spitter", original = "maf-giant-fire-spitter5" },
  { id = "acid-spitter", original = "maf-giant-acid-spitter5" },
}
M.COLOSSUS_PREFIX = "nexus-colossus-"
M.COLOSSUS_HEALTH_SHARE = 0.35 -- Big Monsters spawns these at the evolution of Nexus.

local SPECS = {
  ["arachnid-queen"] = {
    entity = "maf-boss-arachnid-biter-10",
    precursors = { "arachnid-biter-warrior-unit", "arachnid-spitter-bigspitter-unit" },
  },
  ["watcher"] = {
    entity = M.WATCHER,
    precursors = { "flying-electric-unit-3" },
  },
  ["rogue-spidertron"] = {
    entity = M.SPIDERTRON,
    precursors = { "arachnid-biter-tiger-unit" },
  },
  ["twin-maws"] = {
    entity = "maf-worm-boss-fire-shooter",
    precursors = { "behemoth-spitter" },
  },
  ["colossus"] = {
    entity = M.COLOSSUS_PREFIX .. "fire",
    precursors = { "behemoth-biter" },
  },
  ["plague-hulk"] = {
    entity = "tb_infected_ship_boss",
    precursors = { "big-toxic-biter" },
  },
  ["storm-guardian"] = {
    entity = "walking-electric-unit-boss-10",
    precursors = { "walking-electric-unit-3", "flying-electric-unit-3" },
  },
  ["devourer"] = {
    entity = "big-demolisher",
    precursors = { "behemoth-biter" },
  },
  ["last-commander"] = {
    entity = M.COMMANDER,
    precursors = { "bm_fake_human_machine_gunner_5" },
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
      entity = spec.entity,
      precursors = spec.precursors,
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
  { "projectile", "mf-small-atomic-rocket", "Big-Monsters" },
  { "explosion", "big-explosion", "base" },
  { "segmented-unit", "big-demolisher", "space-age" },
  { "planet", "nexus", "Nexus" },
  { "container", "crash-site-spaceship-wreck-medium-1", "base" },
  { "container", "crash-site-spaceship-wreck-medium-2", "base" },
  { "container", "crash-site-spaceship-wreck-medium-3", "base" },
  { "radar", "radar", "base" },
  { "container", "crash-site-spaceship", "base" },
  { "container", "crash-site-spaceship-wreck-big-1", "base" },
  { "container", "crash-site-chest-1", "base" },
  { "constant-combinator", "constant-combinator", "base" },
  { "simple-entity", "fulgoran-ruin-small", "space-age" },
  { "simple-entity", "fulgoran-ruin-medium", "space-age" },
  { "simple-entity", "fulgoran-ruin-vault", "space-age" },
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

---A beacon of the Storm Guardian with charged shards in it.
---@param charge integer 1..M.CHARGES
---@return string
function M.charged_beacon_name(charge)
  return M.beacon_name(M.CHARGED_BOSS) .. "-charged-" .. charge
end

---@param name string entity or item name
---@return string|nil boss id when the name is a beacon
---@return integer charge: the shards in a charged beacon, 0 for any other
function M.boss_of_beacon(name)
  if name:sub(1, #M.BEACON_PREFIX) ~= M.BEACON_PREFIX then
    return nil, 0
  end
  local id = name:sub(#M.BEACON_PREFIX + 1)
  if M.BOSSES[id] then
    return id, 0
  end
  for charge = 1, M.CHARGES do
    if name == M.charged_beacon_name(charge) then
      return M.CHARGED_BOSS, charge
    end
  end
  return nil, 0
end

---Every beacon name: one a boss and the charged ones.
---@return string[]
function M.beacon_names()
  local names = {}
  for _, id in ipairs(M.ORDER) do
    names[#names + 1] = M.beacon_name(id)
  end
  for charge = 1, M.CHARGES do
    names[#names + 1] = M.charged_beacon_name(charge)
  end
  return names
end

return M
