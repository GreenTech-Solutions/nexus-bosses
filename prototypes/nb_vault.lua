-- The vault of the builders (2.5): the glyph signals, the obelisks and the console of the lock at the vault ruin, the
-- hatch down and the stairs up, the reliquary, the relic (mining it researches the Echo of the builders) and the music
-- of the vault. scripts/nb_vault.lua runs it all.

local util = require("util")
local cfg = require("lib.nb_data")

local GATED = settings.startup["nexus-bosses-gate-warp-drive"].value
local ICONS = "__nexus-bosses__/graphics/icons/"
local FLAGS = { "placeable-neutral", "not-rotatable", "placeable-off-grid", "not-blueprintable", "not-deconstructable" }

---The first picture of a ruin of Fulgora.
---@param name string
---@return table
local function ruin_picture(name)
  local ruin = data.raw["simple-entity"][name]
  local picture = util.table.deepcopy(ruin.pictures and ruin.pictures[1] or ruin.picture) --[[@as table]]
  picture["line_length"] = nil
  return picture
end

---@type table[]
local prototypes = {
  { type = "item-subgroup", name = "nexus-bosses-glyphs", group = "signals", order = "z[nexus-bosses-glyphs]" },
}
for index = 1, cfg.GLYPHS do
  prototypes[#prototypes + 1] = {
    type = "virtual-signal",
    name = cfg.GLYPH_PREFIX .. index,
    icon = ICONS .. "glyph-" .. index .. ".png",
    subgroup = "nexus-bosses-glyphs",
    order = "a-" .. index,
  }
end

---A container of the vault: opened, never mined or destroyed.
---@param name string
---@param picture table
---@param slots integer
---@param collision table
local function vault_container(name, picture, slots, collision)
  return {
    type = "container",
    name = name,
    icon = ICONS .. "glyph-8.png",
    flags = FLAGS,
    max_health = 5000,
    collision_box = collision,
    selection_box = { { collision[1][1] - 0.2, collision[1][2] - 0.2 }, { collision[2][1] + 0.2, collision[2][2] + 0.2 } },
    inventory_size = slots,
    inventory_type = "normal",
    picture = picture,
    open_sound = { filename = "__base__/sound/machine-open.ogg", volume = 0.5 },
    close_sound = { filename = "__base__/sound/machine-close.ogg", volume = 0.5 },
  }
end

local console = util.table.deepcopy(data.raw["constant-combinator"]["constant-combinator"]) --[[@as table]]
console.name = cfg.CONSOLE
console.minable = nil
console.flags = { "placeable-neutral", "not-blueprintable", "not-deconstructable" }
console.fast_replaceable_group = nil
console.next_upgrade = nil

local reliquary = util.table.deepcopy(data.raw.container["crash-site-chest-1"]) --[[@as table]]
reliquary.name = cfg.RELIQUARY
reliquary.minable = nil
reliquary.flags = FLAGS
reliquary.inventory_size = 12

prototypes[#prototypes + 1] = {
  type = "simple-entity-with-owner",
  name = cfg.OBELISK,
  icon = ICONS .. "glyph-1.png",
  flags = FLAGS,
  max_health = 5000,
  collision_box = { { -0.7, -0.6 }, { 0.7, 0.6 } },
  selection_box = { { -0.9, -0.8 }, { 0.9, 0.8 } },
  picture = ruin_picture("fulgoran-ruin-small"),
}
prototypes[#prototypes + 1] = console
prototypes[#prototypes + 1] = vault_container(cfg.HATCH, ruin_picture("fulgoran-ruin-medium"), 1, { { -1.2, -0.8 }, { 1.2, 0.8 } })
prototypes[#prototypes + 1] = vault_container(cfg.STAIRS, ruin_picture("fulgoran-ruin-medium"), 1, { { -1.2, -0.8 }, { 1.2, 0.8 } })
prototypes[#prototypes + 1] = reliquary
prototypes[#prototypes + 1] = {
  type = "simple-entity",
  name = cfg.RELIC,
  icon = ICONS .. "builders-relic.png",
  flags = { "placeable-neutral", "placeable-off-grid", "not-on-map" },
  minable = { mining_time = 2, result = cfg.RELIC },
  max_health = 5000,
  collision_box = { { -0.6, -0.6 }, { 0.6, 0.6 } },
  selection_box = { { -0.8, -0.8 }, { 0.8, 0.8 } },
  picture = { filename = "__nexus-bosses__/graphics/entity/builders-relic.png", size = 128, scale = 0.5 },
}
prototypes[#prototypes + 1] = {
  type = "item",
  name = cfg.RELIC,
  icon = ICONS .. "builders-relic.png",
  subgroup = data.raw["item-subgroup"]["omega-threat"] and "omega-threat" or "other",
  order = "y-e[nexus-builders-relic]",
  stack_size = 1,
  weight = 1000000,
}
prototypes[#prototypes + 1] = {
  type = "technology",
  name = cfg.ECHO_TECH,
  icons = {
    { icon = "__nexus-bosses__/graphics/technology/tech-silence.png", icon_size = 256 },
    { icon = ICONS .. "builders-relic.png", icon_size = 64, scale = 1, shift = { 40, 40 } },
  },
  essential = false,
  prerequisites = { GATED and cfg.SILENCE_TECH or cfg.CIRCLES[#cfg.CIRCLES].tech },
  research_trigger = { type = "mine-entity", entities = { cfg.RELIC } },
  effects = { { type = "laboratory-productivity", modifier = 0.1 } },
  order = "fa-b[nexus-signal]-zz",
}
prototypes[#prototypes + 1] = {
  type = "ambient-sound",
  name = cfg.VAULT_TRACK,
  track_type = "script-track",
  sound = { filename = "__TFMG-music__/arrival/Reflections-Interlude.ogg", volume = 0.6 },
}

data:extend(prototypes)
