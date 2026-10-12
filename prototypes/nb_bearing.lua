-- Bearings (2.3): the direction finder (a radar of the signal, scripts/nb_bearing.lua draws its bearings), the
-- technology that unlocks it (scripted: the first log of the expedition found) and the remains that mark a found lair
-- (copies of the corpses of the bosses that stay for good).

local util = require("util")
local cfg = require("lib.nb_data")
local proto = require("prototypes.nb_util")

local TINT = { r = 0.75, g = 0.55, b = 1 }
-- a sector every ~20 s on full power: the bearing narrows with every sector
local ENERGY_USAGE = "2MW"
local ENERGY_PER_SECTOR = "40MJ"

local finder = util.table.deepcopy(data.raw.radar.radar)
finder.name = cfg.FINDER
finder.icons = { { icon = finder.icon or "__base__/graphics/icons/radar.png", icon_size = finder.icon_size or 64, tint = TINT } }
finder.icon = nil
finder.minable = { mining_time = 0.5, result = cfg.FINDER }
finder.fast_replaceable_group = nil
finder.next_upgrade = nil
finder.max_health = 500
finder.energy_usage = ENERGY_USAGE
finder.energy_per_sector = ENERGY_PER_SECTOR
finder.max_distance_of_sector_revealed = 4
finder.max_distance_of_nearby_sector_revealed = 2
finder.connects_to_other_radars = false
finder.radius_minimap_visualisation_color = { r = 0.3, g = 0.15, b = 0.45, a = 0.275 }
local pictures = assert(finder.pictures, "nexus-bosses: the radar has no pictures")
for _, layer in ipairs(pictures.layers or { pictures }) do
  if not layer.draw_as_shadow then
    layer.tint = TINT
  end
end

data:extend({
  finder,
  {
    type = "item",
    name = cfg.FINDER,
    icons = finder.icons,
    subgroup = data.raw["item-subgroup"]["omega-threat"] and "omega-threat" or "other",
    order = "y-a[nexus-direction-finder]",
    place_result = cfg.FINDER,
    stack_size = 10,
    weight = 50000,
  },
  {
    type = "recipe",
    name = cfg.FINDER,
    enabled = false,
    energy_required = 20,
    ingredients = {
      { type = "item", name = "radar", amount = 1 },
      { type = "item", name = cfg.ALLOY_ITEM, amount = 20 },
      { type = "item", name = cfg.PROCESSOR_ITEM, amount = 2 },
    },
    results = { { type = "item", name = cfg.FINDER, amount = 1 } },
  },
})

-- The remains of a lair: the corpse of the boss, staying for good (a corpse of the game disappears in minutes). Only a
-- prototype of type corpse will do: some bosses leave a simple-entity (an obstacle for good) or a character corpse.
local YEAR_TICKS = 60 * 60 * 60 * 24 * 365
local FALLBACK = { devourer = "big-demolisher-fissure-scorchmark" }
for _, id in ipairs(cfg.ORDER) do
  local boss = proto.find_entity(cfg.BOSSES[id].entity)
  local corpse_name = boss and boss.corpse
  if type(corpse_name) == "table" then
    corpse_name = corpse_name[1]
  end
  local corpse = data.raw.corpse[corpse_name or ""] or data.raw.corpse[FALLBACK[id] or ""] or data.raw.corpse["big-remnants"]
  local remains = util.table.deepcopy(corpse)
  remains.name = cfg.LAIR_REMAINS_PREFIX .. id
  remains.localised_name = { "entity-name.nexus-bosses-lair-remains", { "nexus-bosses.boss-" .. id } }
  remains.time_before_removed = YEAR_TICKS
  remains.remove_on_entity_placement = true
  remains.flags = { "placeable-neutral", "not-on-map", "placeable-off-grid" }
  remains.minable = nil
  data:extend({ remains })
end

if data.raw.corpse["big-scorchmark"] then
  local scorch = util.table.deepcopy(data.raw.corpse["big-scorchmark"])
  scorch.name = cfg.LAIR_SCORCH
  scorch.time_before_removed = YEAR_TICKS
  data:extend({ scorch })
end

-- The pylon of suppression of a lair (2.4): a container of one slot, drawn as a ruin of Fulgora. A trophy put in it
-- repairs it (scripts/nb_bearing.lua); the repaired look is drawn by the script.
local ruin = data.raw["simple-entity"]["fulgoran-ruin-stonehenge"]
local picture = ruin and util.table.deepcopy(ruin.pictures and ruin.pictures[1] or ruin.picture) --[[@as table|nil]]
if picture then
  picture["line_length"] = nil
end
data:extend({
  {
    type = "container",
    name = cfg.PYLON,
    icon = "__nexus-bosses__/graphics/technology/tech-silence.png",
    icon_size = 256,
    flags = { "placeable-neutral", "not-rotatable", "not-blueprintable", "not-deconstructable", "placeable-off-grid" },
    max_health = 5000,
    collision_box = ruin and ruin.collision_box or { { -1.5, -1.3 }, { 1.5, 1.3 } },
    selection_box = { { -1.6, -1.4 }, { 1.6, 1.4 } },
    inventory_size = 1,
    inventory_type = "normal",
    picture = picture or { filename = "__core__/graphics/empty.png", size = 1 },
    open_sound = { filename = "__base__/sound/machine-open.ogg", volume = 0.5 },
    close_sound = { filename = "__base__/sound/machine-close.ogg", volume = 0.5 },
  },
})
