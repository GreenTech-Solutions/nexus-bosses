-- Big-Monsters random events are switched off by default: on Nexus its bosses come only from our
-- summon beacons (control.lua calls its remote interface), and nothing should hit the other planets
-- out of the blue. The player can still turn any of them back on in the map settings.
--
-- Every access is guarded: a setting that Big-Monsters renames or removes must not break the load.

local function set_default(setting_type, name, value)
  local group = data.raw[setting_type]
  local setting = group and group[name]
  if setting and setting.default_value ~= value then
    setting.default_value = value
  end
end

-- chances of the random events (int-setting, 0-80 %)
for _, name in ipairs({
  "bm-invasion-chance",
  "bm-soldiers-chance",
  "bm-gleba-invaders-chance",
  "bm-worms-chance",
  "bm-biterzilla-chance",
  "bm-spidertron-chance",
  "bm-demolisher-chance",
  "bm-volcano-chance",
  "bm-swarm-chance",
}) do
  set_default("int-setting", name, 0)
end

-- the two double settings: the flying saucer chance and the chance of an event when a tree is mined
set_default("double-setting", "bm-flying-saucer-chance", 0)
set_default("double-setting", "bm-tree-events-chance", 0)

-- attacks on rocket silos
set_default("bool-setting", "bm-enable-silo-attack", false)

-- No nuke-rocket soldiers: with this on, the brood of the Final Boss (Big-Monsters' BroodHumans, at the evolution of
-- Nexus) includes bm_fake_human_nuke_rocket_*, soldiers that launch atomic rockets. (The Final Boss itself still throws
-- the small atomic rockets that Big-Monsters gives it; that is part of its design and is not a setting.)
set_default("bool-setting", "bm-allow-nuker", false)

-- The values below are Big-Monsters' own defaults, written down here so that they are a decision of this mod: no
-- atomic rockets in the spidertron, the difficulty level and the health multiplier of the big enemies at 1. The other
-- startup multipliers (bm-enemy-hp-multiplier, bm-worm-enemy-hp-multiplier, bm-big-enemy-hp-variant,
-- bm-enemy-damage-multiplier) stay the player's choice and scale the bosses of Big-Monsters.
set_default("bool-setting", "bm-spidertron-nuke", false)
set_default("int-setting", "bm-difficulty-level", 1)
set_default("double-setting", "bm-big-enemy-hp-multiplier", 1)
