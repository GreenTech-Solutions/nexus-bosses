-- The nine summon beacons: an item, a recipe and a placeable 2x2 entity for every boss.
--
-- Recipe. 100 / 300 / 900 omega alloy and 5 / 15 / 45 advanced photon processors by circle, times the startup setting
-- "nexus-bosses-beacon-cost" (at least one of each). The category is
-- "crafting-with-fluid", the one the recipe of the shield stabilizer (the other capital item of Nexus, subgroup
-- omega-threat) uses: an assembling machine 2 or better crafts it, the player cannot hand-craft it, and it needs
-- none of the special machines of Nexus (the ingredients come from them anyway). The time grows with the circle,
-- 30 / 60 / 120 s (the stabilizer takes 60 s). The surface conditions are the ones of the Nexus recipes, so the
-- beacons can be crafted on Nexus only.
--
-- Entity. A simple-entity-with-owner: it has a force, health and a mining result, nothing else. Immune to
-- electric damage (the lightning of the storms must not cancel a summon), destructible (it is a military target,
-- enemies attack it), and it leaves no ghost behind when destroyed (robots would pay for a new summon).
-- The graphics are the omega beacon of Nexus-Graphics (or of its 2.1 fork Nexus-Graphics-Updated), scaled down to 2x2,
-- with an antenna tinted by circle.
--
-- Description. The text of the locale, then the resistances of the boss (prototypes/nb_hints.lua), so that the fight can
-- be prepared for.

local cfg = require("lib.nb_data")
local proto = require("prototypes.nb_util")
local hints = require("prototypes.nb_hints")

local subgroup = (data.raw["item-subgroup"] and data.raw["item-subgroup"]["omega-threat"]) and "omega-threat" or "other"

-- antenna tint by circle: blue, amber, red
local TINTS = {
  { r = 0.55, g = 0.85, b = 1.0 },
  { r = 1.0, g = 0.8, b = 0.35 },
  { r = 1.0, g = 0.4, b = 0.35 },
}

local SCALE = 0.7 -- the omega beacon is 3x3, the summon beacon 2x2
-- The graphics mod of Nexus: the 2.1 fork, or the original once it has a 2.1 release; nil without either.
local GRAPHICS = (mods["Nexus-Graphics-Updated"] and "__Nexus-Graphics-Updated__/graphics/")
  or (mods["Nexus-Graphics"] and "__Nexus-Graphics__/graphics/")
  or nil

local COST = settings.startup["nexus-bosses-beacon-cost"].value --[[@as number]]

---@param amount integer
---@return integer
local function cost(amount)
  return math.max(1, math.floor(amount * COST + 0.5))
end

local function by_pixel(x, y)
  return { x / 32 * SCALE, y / 32 * SCALE }
end

local function entity_layers(circle)
  if GRAPHICS then
    return {
      {
        filename = GRAPHICS .. "entity/omega-beacon.png",
        width = 232,
        height = 186,
        scale = 0.525 * SCALE,
        shift = by_pixel(13, 1.5),
        frame_count = 1,
        repeat_count = 32,
        priority = "high",
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
        priority = "high",
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
        priority = "high",
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
        priority = "high",
      },
    }
  end
  -- The graphics mod comes with Nexus, so this is not reached in a working game; the base beacon keeps the prototype
  -- valid anyway.
  return {
    {
      filename = "__base__/graphics/entity/beacon/beacon-bottom.png",
      width = 212,
      height = 192,
      scale = 0.5 * SCALE * 1.15,
      shift = by_pixel(0.5, 1),
      frame_count = 1,
      repeat_count = 45,
    },
    {
      filename = "__base__/graphics/entity/beacon/beacon-top.png",
      width = 96,
      height = 140,
      scale = 0.5 * SCALE * 1.15,
      shift = by_pixel(3, -19),
      tint = TINTS[circle],
      frame_count = 1,
      repeat_count = 45,
    },
  }
end

local omega_beacon_icon = proto.icon_layer(data.raw.item and data.raw.item["omega-beacon"])
  or { icon = "__base__/graphics/icons/beacon.png", icon_size = 64 }

local function item_icons(id)
  local icons = { { icon = omega_beacon_icon.icon, icon_size = omega_beacon_icon.icon_size } }
  local boss_icon = proto.first_icon(cfg.BOSSES[id].icon_from)
  if boss_icon then
    -- the boss in the lower right corner (the canvas of an item icon is 32 px wide)
    icons[#icons + 1] = {
      icon = boss_icon.icon,
      icon_size = boss_icon.icon_size,
      scale = 0.28 * 64 / boss_icon.icon_size,
      shift = { 7, 7 },
      draw_background = true,
    }
  end
  return icons
end

for _, id in ipairs(cfg.ORDER) do
  local boss = cfg.BOSSES[id]
  local circle = cfg.CIRCLES[boss.circle]
  local name = cfg.beacon_name(id)
  local order = string.format("y-b[nexus-summon]-%d%d", boss.circle, boss.slot)
  local hint = hints.hint(id)
  if not hint then
    log("[nexus-bosses] no prototype to tell the resistances of " .. id .. ": the beacon has no hint")
  end
  ---@param kind string "item" or "entity"
  local function description(kind)
    -- the boss, then the rules that are the same for every beacon, then what the boss resists
    local text = { "", { kind .. "-description." .. name }, "\n", { "nexus-bosses.beacon-rules-" .. kind } }
    if hint then
      return { "", text, "\n", hint }
    end
    return text
  end

  data:extend({
    {
      type = "item",
      name = name,
      icons = item_icons(id),
      localised_description = description("item"),
      subgroup = subgroup,
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
      main_product = name,
      surface_conditions = proto.nexus_surface_conditions(),
      allow_productivity = false,
      allow_quality = false,
      auto_recycle = false,
      subgroup = subgroup,
      order = order,
    },
    {
      type = "simple-entity-with-owner",
      name = name,
      icons = item_icons(id),
      localised_description = description("entity"),
      flags = { "placeable-neutral", "player-creation", "not-rotatable", "not-blueprintable" },
      minable = { mining_time = 1, result = name },
      placeable_by = { item = name, count = 1 },
      max_health = 500,
      resistances = { { type = "electric", percent = 100 } },
      is_military_target = true,
      create_ghost_on_death = false,
      dying_explosion = "medium-explosion",
      collision_box = { { -0.9, -0.9 }, { 0.9, 0.9 } },
      selection_box = { { -1, -1 }, { 1, 1 } },
      drawing_box_vertical_extension = 1,
      surface_conditions = proto.nexus_surface_conditions(),
      animations = { layers = entity_layers(boss.circle) },
      subgroup = subgroup,
      order = order,
    },
  })
end
