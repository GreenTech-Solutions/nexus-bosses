-- The summon beacons (item, recipe, placeable entity), the trophies of the bosses and the warp key.
--
-- A beacon is crafted on Nexus only, in an assembling machine ("crafting-with-fluid", like the shield stabilizer).
-- Its entity is a simple-entity-with-owner: a force, health and a mining result. Lightning does not hurt it, enemies
-- do (it is a military target, the precursors come for it), and it leaves no ghost: robots would pay for a new summon.
-- The graphics are the omega beacon of the Nexus graphics mod, scaled to 2x2, with an antenna tinted by circle.

local cfg = require("lib.nb_data")
local proto = require("prototypes.nb_util")

local COST = settings.startup["nexus-bosses-beacon-cost"].value --[[@as number]]
-- Nexus-Threat makes the subgroup only while its startup setting nexus-threat-activation is on
local SUBGROUP = data.raw["item-subgroup"]["omega-threat"] and "omega-threat" or "other"
local GRAPHICS
if mods["Nexus-Graphics-Updated"] then
  GRAPHICS = "__Nexus-Graphics-Updated__/graphics/"
elseif mods["Nexus-Graphics"] then
  GRAPHICS = "__Nexus-Graphics__/graphics/"
else
  error("nexus-bosses: needs Nexus-Graphics-Updated or Nexus-Graphics")
end

-- antenna tint by circle: blue, amber, red
local TINTS = {
  { r = 0.55, g = 0.85, b = 1.0 },
  { r = 1.0, g = 0.8, b = 0.35 },
  { r = 1.0, g = 0.4, b = 0.35 },
}
local SCALE = 0.7 -- the omega beacon is 3x3

---@param amount integer
---@return integer
local function cost(amount)
  return math.max(1, math.floor(amount * COST + 0.5))
end

local function by_pixel(x, y)
  return { x / 32 * SCALE, y / 32 * SCALE }
end

local function beacon_layers(circle)
  return {
    {
      filename = GRAPHICS .. "entity/omega-beacon.png",
      width = 232,
      height = 186,
      scale = 0.525 * SCALE,
      shift = by_pixel(13, 1.5),
      frame_count = 1,
      repeat_count = 32,
    },
    {
      filename = GRAPHICS .. "entity/omega-beacon-shadow.png",
      width = 232,
      height = 186,
      scale = 0.5 * SCALE,
      shift = by_pixel(13, 1.5),
      draw_as_shadow = true,
      frame_count = 1,
      repeat_count = 32,
    },
    {
      filename = GRAPHICS .. "entity/omega-beacon-animation.png",
      width = 108,
      height = 100,
      line_length = 8,
      frame_count = 32,
      animation_speed = 0.5,
      scale = 0.5 * SCALE,
      shift = by_pixel(1, -57),
      tint = TINTS[circle],
    },
    {
      filename = GRAPHICS .. "entity/omega-beacon-top-shadow.png",
      width = 126,
      height = 98,
      line_length = 8,
      frame_count = 32,
      animation_speed = 0.5,
      scale = 0.5 * SCALE,
      shift = by_pixel(102.5, 17.5),
      draw_as_shadow = true,
    },
  }
end

local omega_beacon = proto.icon_layer(data.raw.item["omega-beacon"])

---The omega beacon with the boss in the lower right corner (an item icon is 32 px wide in layer coordinates).
local function beacon_icons(id)
  local boss = proto.entity_icon(cfg.BOSSES[id].entity)
  return {
    { icon = omega_beacon.icon, icon_size = omega_beacon.icon_size },
    {
      icon = boss.icon,
      icon_size = boss.icon_size,
      scale = 0.28 * 64 / boss.icon_size,
      shift = { 7, 7 },
      draw_background = true,
    },
  }
end

local conditions = proto.nexus_surface_conditions()

for _, id in ipairs(cfg.ORDER) do
  local boss = cfg.BOSSES[id]
  local circle = cfg.CIRCLES[boss.circle]
  local name = cfg.beacon_name(id)
  local order = string.format("y-b[nexus-summon]-%d%d", boss.circle, boss.slot)
  -- stage, who comes, how to fight it, then the rules of every beacon
  local description = {
    "",
    { "nexus-bosses.beacon-stage", { "nexus-bosses.stage-" .. circle.stage } },
    " ",
    { "nexus-bosses.lore-" .. id },
    "\n\n",
    { "nexus-bosses.tactic-" .. id },
    "\n\n",
    { "nexus-bosses.beacon-rules" },
  }

  data:extend({
    {
      type = "item",
      name = name,
      localised_name = { "nexus-bosses.beacon-name", { "nexus-bosses.boss-" .. id } },
      localised_description = description,
      icons = beacon_icons(id),
      subgroup = SUBGROUP,
      order = order,
      stack_size = 5,
      weight = 50000,
      place_result = name,
    },
    {
      type = "recipe",
      name = name,
      enabled = false,
      energy_required = circle.seconds,
      categories = { "crafting-with-fluid" },
      ingredients = {
        { type = "item", name = cfg.ALLOY_ITEM, amount = cost(circle.alloy) },
        { type = "item", name = cfg.PROCESSOR_ITEM, amount = cost(circle.processors) },
      },
      results = { { type = "item", name = name, amount = 1 } },
      surface_conditions = conditions,
      allow_productivity = false,
      allow_quality = false,
      auto_recycle = false,
    },
    {
      type = "simple-entity-with-owner",
      name = name,
      localised_name = { "nexus-bosses.beacon-name", { "nexus-bosses.boss-" .. id } },
      localised_description = description,
      icons = beacon_icons(id),
      flags = { "placeable-neutral", "player-creation", "not-rotatable", "not-blueprintable" },
      minable = { mining_time = 1, result = name },
      placeable_by = { item = name, count = 1 },
      max_health = 3000,
      resistances = { { type = "electric", percent = 100 } },
      is_military_target = true,
      create_ghost_on_death = false,
      dying_explosion = "medium-explosion",
      collision_box = { { -0.9, -0.9 }, { 0.9, 0.9 } },
      selection_box = { { -1, -1 }, { 1, 1 } },
      drawing_box_vertical_extension = 1,
      surface_conditions = conditions,
      animations = { layers = beacon_layers(boss.circle) },
      subgroup = SUBGROUP,
      order = order,
    },
  })
end

-- Trophies: one drops where a boss dies, at every victory. The warp key takes one of each (only while the trials gate
-- the warp drive: without the gate there is no key).
local GATED = settings.startup["nexus-bosses-gate-warp-drive"].value
local ICONS = "__nexus-bosses__/graphics/icons/"

local key_ingredients = {}
for _, id in ipairs(cfg.ORDER) do
  local boss = cfg.BOSSES[id]
  local name = cfg.trophy_name(id)
  data:extend({
    {
      type = "item",
      name = name,
      localised_name = { "item-name." .. name },
      localised_description = GATED and { "", { "item-description." .. name }, " ", { "nexus-bosses.trophy-key-part" } }
        or { "item-description." .. name },
      icon = ICONS .. "trophy-" .. id .. ".png",
      subgroup = SUBGROUP,
      order = string.format("y-c[nexus-trophy]-%d%d", boss.circle, boss.slot),
      stack_size = 10,
      weight = 100000,
    },
  })
  key_ingredients[#key_ingredients + 1] = { type = "item", name = name, amount = 1 }
end

if GATED then
  data:extend({
    {
      type = "item",
      name = cfg.WARP_KEY,
      icon = ICONS .. "warp-key.png",
      subgroup = SUBGROUP,
      order = "y-d[nexus-warp-key]",
      stack_size = 1,
      weight = 1000000,
    },
    {
      type = "recipe",
      name = cfg.WARP_KEY,
      enabled = false,
      energy_required = 10,
      ingredients = key_ingredients,
      results = { { type = "item", name = cfg.WARP_KEY, amount = 1 } },
      allow_productivity = false,
      allow_quality = false,
      auto_recycle = false,
    },
  })
end
