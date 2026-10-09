-- Constants shared by the data stage (prototypes) and the control stage (scripts).
-- Pure Lua: no game API, no prototype access.

---@class NbCircle
---@field tech string technology whose researching unlocks the beacons of the circle
---@field reward string technology researched when the three bosses of the circle are beaten
---@field bosses string[]
---@field alloy integer omega alloy per beacon
---@field processors integer advanced photon processors per beacon
---@field seconds number crafting time of a beacon

---@class NbBossSpec
---@field kind "own"|"bm" "own": the mod spawns the boss (scripts/nb_spawn.lua), "bm": Big-Monsters does (scripts/nb_bm.lua)
---@field watch string[] entity prototypes whose death is the victory (kind "own")
---@field icon_from string[][] candidate prototypes {type, name} whose icon marks the beacon and the technology
---@field hint_from string[][]|nil kind "own": the prototypes {type, name} whose resistances the beacon tells; the first one that exists
---@field circle integer
---@field slot integer

---@class NbBmSet
---@field event string event of the remote interface "bigmonster"
---@field types string[] entity types of the bosses
---@field prefixes string[] name prefixes of the bosses
---@field explore_chunks integer chunk radius around the spawn of the force that is generated for the event
---@field hint_names string[] the bosses that the event creates at the evolution of Nexus (their resistances are told)

local M = {}

M.PLANET = "nexus"

-- Enemy evolution of the enemy force on the Nexus surface. Big-Monsters picks the strongest variants of its
-- bosses from it, the spawner of the Toxic Lair picks the tiers of its guards.
M.EVOLUTION = 0.99
M.EVOLUTION_REFRESH_TICKS = 60 * 60

-- Multiplier of the storm strength after the Storm Guardian falls (remote interface "nexus-threat").
M.STORM_MULTIPLIER = 0.5

M.BEACON_PREFIX = "nexus-summon-"

M.COMPLETE_TECH = "nexus-trials-complete"

-- The technology that opens the first circle. When the shield stabilizer (the trigger of the first circle) does not
-- exist, the script researches the first circle as soon as this one is researched.
M.PLANET_TECH = "planet-discovery-nexus"

-- Health of the bosses that the mod makes from prototypes of other mods, before the startup setting
-- "nexus-bosses-boss-health" scales it. The spawner of the Toxic Lair grows with the
-- evolution (see prototypes/nb_enemies.lua); the Host Worm regenerates 50 health per tick = 3 000 per second, which is
-- 0.06 % of its health (the big demolisher it is copied from regenerates 24 000 per second, 8 % of its 300 000).
M.LAIR_HEALTH = 2000000
M.WORM_HEALTH = 5000000
M.WORM_HEALING_PER_TICK = 50

-- What a beacon tells about its boss (prototypes/nb_hints.lua): a resistance is worth mentioning from this percent or
-- this flat decrease on, a negative one is a weakness from this percent on, and regeneration from this many health
-- per second on.
M.HINT_MIN_PERCENT = 30
M.HINT_MIN_FLAT = 20
M.HINT_WEAK_PERCENT = -20
M.HINT_MIN_REGEN = 100

---@type string[]
M.ROMAN = { "I", "II", "III" }

-- The three circles. `tech` unlocks the recipes of the beacons of the circle; when all its bosses are beaten
-- the technology `reward` is researched (scripted trigger), which opens the next circle or, after the last
-- one, the way to the warp drive. The cost of a beacon: omega alloy, advanced photon processors, seconds.
---@type NbCircle[]
M.CIRCLES = {
  {
    tech = "nexus-trials-1",
    reward = "nexus-trials-2",
    bosses = { "arachnid-queen", "flying-saucer", "evil-spider" },
    alloy = 100,
    processors = 5,
    seconds = 30,
  },
  {
    tech = "nexus-trials-2",
    reward = "nexus-trials-3",
    bosses = { "great-worms", "biterzilla", "toxic-lair" },
    alloy = 300,
    processors = 15,
    seconds = 60,
  },
  {
    tech = "nexus-trials-3",
    reward = M.COMPLETE_TECH,
    bosses = { "storm-guardian", "host-worm", "final-boss" },
    alloy = 900,
    processors = 45,
    seconds = 120,
  },
}

M.ALLOY_ITEM = "omega-alloy"
M.PROCESSOR_ITEM = "advanced-photon-processor"

local SPECS = {
  ["arachnid-queen"] = {
    kind = "own",
    watch = { "maf-boss-arachnid-biter-10", "nexus-arachnid-queen" },
    icon_from = { { "unit", "maf-boss-arachnid-biter-10" } },
    hint_from = { { "unit", "nexus-arachnid-queen" }, { "unit", "maf-boss-arachnid-biter-10" } },
  },
  ["flying-saucer"] = {
    kind = "bm",
    watch = {},
    icon_from = { { "spider-vehicle", "maf_flying_saucer_1" } },
  },
  ["evil-spider"] = {
    kind = "bm",
    watch = {},
    icon_from = { { "spider-vehicle", "bm-spidertron_1" } },
  },
  ["great-worms"] = {
    kind = "bm",
    watch = {},
    icon_from = { { "turret", "maf-worm-boss-fire-shooter" }, { "turret", "bm-worm-boss-acid-shooter" } },
  },
  ["biterzilla"] = {
    kind = "bm",
    watch = {},
    icon_from = { { "unit", "biterzilla11" }, { "unit", "bm-motherbiterzilla1" } },
  },
  ["toxic-lair"] = {
    kind = "own",
    watch = { "nexus-toxic-lair" },
    icon_from = { { "unit-spawner", "tb_infected_ship_boss" } },
    hint_from = { { "unit-spawner", "nexus-toxic-lair" } }, -- the spawner itself, not the units it makes
  },
  ["storm-guardian"] = {
    kind = "own",
    watch = { "walking-electric-unit-boss-10", "nexus-storm-guardian" },
    icon_from = { { "unit", "walking-electric-unit-boss-10" } },
    hint_from = { { "unit", "nexus-storm-guardian" }, { "unit", "walking-electric-unit-boss-10" } },
  },
  ["host-worm"] = {
    kind = "own",
    watch = {}, -- a segmented unit: its death is a different event (on_segmented_unit_died)
    icon_from = { { "segmented-unit", "big-demolisher" } },
    hint_from = { { "segmented-unit", "nexus-host-worm" } },
  },
  ["final-boss"] = {
    kind = "bm",
    watch = {},
    icon_from = { { "unit", "bm_fake_human_ultimate_boss_cannon_20" } },
  },
}

-- Boss ids in the order of the circles, and the specification of every boss with its circle and slot.
---@type string[]
M.ORDER = {}
---@type table<string, NbBossSpec>
M.BOSSES = {}
for circle_index, circle in ipairs(M.CIRCLES) do
  for slot, id in ipairs(circle.bosses) do
    local spec = assert(SPECS[id], "nexus-bosses: no specification for the boss " .. id)
    M.ORDER[#M.ORDER + 1] = id
    M.BOSSES[id] = {
      kind = spec.kind,
      watch = spec.watch,
      icon_from = spec.icon_from,
      hint_from = spec.hint_from,
      circle = circle_index,
      slot = slot,
    }
  end
end

-- The bosses of Big-Monsters: which of its events makes them and how to recognise them among the entities
-- of the Nexus surface. The lists of names are built at run time from the prototypes (types and prefixes),
-- so corpses and other prototypes with the same prefix never count.
--
-- explore_chunks: Big-Monsters (2.2.1, FindTeamAttackCorner) walks from the spawn of the force along a random line
-- through generated chunks and places the boss where it meets enough chunks without buildings of the force and then
-- an ungenerated one; with too little generated land it silently creates nothing. The mod asks the map generator for
-- this chunk radius around the spawn when a summon starts. Measured on Nexus (30 calls per cell): the final boss
-- (10 empty chunks needed) succeeds 4/30 calls at radius 16 and 18/30 at 24, the others 27-30/30 at 16.
--
-- hint_names: what the event creates at the evolution that Nexus is pinned at (0.99), read from the code of
-- Big-Monsters 2.2.1: the saucer of tier 8 and the spidertron of tier 5; the boss worms; the giants of tier 5
-- (biterzilla1-3 + 5, maf-giant-*-spitter5, bm-motherbiterzilla5); the ultimate boss. Biterzilla's optional human
-- bosses are an exception: its call does not pass the Nexus surface, so Big-Monsters reads global evolution instead.
-- Include every selectable human type and tier in that hint to report only resistances common to all of them.
local BITERZILLA_HINT_NAMES = {
  "biterzilla15", "biterzilla25", "biterzilla35",
  "maf-giant-acid-spitter5", "maf-giant-fire-spitter5", "bm-motherbiterzilla5",
}
local BITERZILLA_HUMAN_BOSS_TYPES = {
  "bm_fake_human_boss_machine_gunner", "bm_fake_human_boss_laser", "bm_fake_human_boss_electric",
  "bm_fake_human_flamethrower", "bm_fake_human_boss_sniper", "bm_fake_human_boss_rocket",
  "bm_fake_human_boss_grenade", "bm_fake_human_boss_erocket", "bm_fake_human_boss_cluster_grenade",
  "bm_fake_human_boss_cannon_explosive",
}
for tier = 1, 10 do
  for _, name in ipairs(BITERZILLA_HUMAN_BOSS_TYPES) do
    BITERZILLA_HINT_NAMES[#BITERZILLA_HINT_NAMES + 1] = name .. "_" .. tier
  end
end

---@type table<string, NbBmSet>
M.BM_SETS = {
  ["flying-saucer"] = {
    event = "flying_saucer",
    types = { "spider-vehicle" },
    prefixes = { "maf_flying_saucer_" },
    explore_chunks = 16,
    hint_names = { "maf_flying_saucer_8" },
  },
  ["evil-spider"] = {
    event = "spidertron",
    types = { "spider-vehicle" },
    prefixes = { "bm-spidertron_" },
    explore_chunks = 16,
    hint_names = { "bm-spidertron_5" },
  },
  ["great-worms"] = {
    event = "worms",
    types = { "turret" },
    prefixes = { "maf-worm-boss-", "bm-worm-boss-" },
    explore_chunks = 16,
    hint_names = { "maf-worm-boss-fire-shooter", "bm-worm-boss-acid-shooter" },
  },
  -- With a positive soldier chance, Biterzilla can pick a human boss. Big-Monsters 2.2.1's human picker also uses
  -- bm_fake_human_flamethrower_* (without "boss" in the name), so it needs its own tracking prefix.
  ["biterzilla"] = {
    event = "biterzilla",
    types = { "unit" },
    prefixes = {
      "biterzilla", "maf-giant-", "bm-motherbiterzilla", "bm_fake_human_boss_", "bm_fake_human_flamethrower_",
    },
    explore_chunks = 16,
    hint_names = BITERZILLA_HINT_NAMES,
  },
  ["final-boss"] = {
    event = "ultimate_boss",
    types = { "unit" },
    prefixes = { "bm_fake_human_ultimate_boss_" },
    explore_chunks = 24,
    hint_names = { "bm_fake_human_ultimate_boss_cannon_20" },
  },
}

---@param id string boss id
---@return string
function M.beacon_name(id)
  return M.BEACON_PREFIX .. id
end

---@param name string entity or item name
---@return string|nil boss id when the name is one of the beacons
function M.boss_of_beacon(name)
  if name:sub(1, #M.BEACON_PREFIX) ~= M.BEACON_PREFIX then
    return nil
  end
  local id = name:sub(#M.BEACON_PREFIX + 1)
  if M.BOSSES[id] then
    return id
  end
  return nil
end

return M
