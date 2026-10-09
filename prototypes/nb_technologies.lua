-- The trials: three circles and the end. No science cost, only triggers.
--   nexus-trials-1         after planet-discovery-nexus; researched by building the shield stabilizer. The stabilizer
--                          belongs to Nexus-Threat and exists only while its startup setting nexus-threat-activation is
--                          on; without it the trigger would name an entity that does not exist (the whole pack would
--                          not load), so the first circle gets a scripted trigger instead and the script researches it
--                          as soon as planet-discovery-nexus is researched (scripts/nb_progress.lua)
--   nexus-trials-2, -3     researched by the script (LuaForce::script_trigger_research) when the three bosses of the
--                          previous circle are beaten
--   nexus-trials-complete  the same after circle III; added to the prerequisites of warp-drive-engine
-- The technology names end with numbers, which the game would treat as levels of one technology for localisation
-- purposes, so the names and descriptions are given explicitly.

local cfg = require("lib.nb_data")
local proto = require("prototypes.nb_util")

local DIGITS = "__base__/graphics/icons/signal/signal_%d.png"
local CHECK = "__base__/graphics/icons/signal/signal-checked-green.png"

local base_icon = proto.icon_layer(data.raw.technology and data.raw.technology[cfg.PLANET_TECH])
  or { icon = "__base__/graphics/technology/military.png", icon_size = 256 }

-- Tech icons have a canvas of 128 px in these layer coordinates, item icons of 32 px.
local function base_layer()
  return { icon = base_icon.icon, icon_size = base_icon.icon_size }
end

local function circle_icons(circle_index)
  local icons = { base_layer() }
  -- the first boss of the circle in the lower right corner, the number of the circle in the lower left one
  local first_boss = assert(cfg.CIRCLES[circle_index].bosses[1])
  local boss_icon = proto.first_icon(cfg.BOSSES[first_boss].icon_from)
  if boss_icon then
    icons[#icons + 1] = {
      icon = boss_icon.icon,
      icon_size = boss_icon.icon_size,
      scale = 64 / boss_icon.icon_size,
      shift = { 30, 30 },
      draw_background = true,
    }
  end
  icons[#icons + 1] = {
    icon = string.format(DIGITS, circle_index),
    icon_size = 64,
    scale = 1,
    shift = { -30, 30 },
    draw_background = true,
  }
  return icons
end

local function complete_icons()
  return {
    base_layer(),
    { icon = CHECK, icon_size = 64, scale = 1.3, shift = { 20, 20 }, draw_background = true },
  }
end

-- The entity the shield stabilizer item places: the trigger of the first circle. nil when Nexus-Threat does not make it.
local stabilizer_item = data.raw.item and data.raw.item["shield-stabilizer"]
local stabilizer_name = stabilizer_item and stabilizer_item.place_result or "shield-stabilizer-1"
---@type string|nil
local stabilizer = stabilizer_name
if not proto.find_entity(stabilizer_name) then
  log("[nexus-bosses] the entity " .. stabilizer_name .. " does not exist (Nexus-Threat is switched off?): the first " ..
    "circle is researched by the script once " .. cfg.PLANET_TECH .. " is researched")
  stabilizer = nil
end

local function unlock_effects(circle_index)
  local effects = {}
  for _, id in ipairs(cfg.CIRCLES[circle_index].bosses) do
    effects[#effects + 1] = { type = "unlock-recipe", recipe = cfg.beacon_name(id) }
  end
  return effects
end

for index, circle in ipairs(cfg.CIRCLES) do
  local research_trigger
  local description = { "technology-description." .. circle.tech }
  if index == 1 and stabilizer then
    research_trigger = { type = "build-entity", entity = stabilizer }
  elseif index == 1 then
    research_trigger = {
      type = "scripted",
      trigger_description = { "nexus-bosses.trigger-trials-start" },
    }
    description = { "technology-description." .. circle.tech .. "-scripted" }
  else
    research_trigger = {
      type = "scripted",
      trigger_description = { "nexus-bosses.trigger-circle-" .. (index - 1) },
    }
    local previous_boss = cfg.CIRCLES[index - 1].bosses[1]
    local trigger_icon = proto.first_icon(cfg.BOSSES[previous_boss].icon_from)
    if trigger_icon then
      research_trigger.icons = { { icon = trigger_icon.icon, icon_size = trigger_icon.icon_size } }
    end
  end

  data:extend({
    {
      type = "technology",
      name = circle.tech,
      localised_name = { "technology-name." .. circle.tech },
      localised_description = description,
      icons = circle_icons(index),
      essential = true,
      show_levels_info = false, -- the number of the circle is already on the icon
      prerequisites = { index == 1 and cfg.PLANET_TECH or cfg.CIRCLES[index - 1].tech },
      research_trigger = research_trigger,
      effects = unlock_effects(index),
      order = "fa-b[nexus-trials]-" .. index,
    },
  })
end

local last_boss = cfg.CIRCLES[#cfg.CIRCLES].bosses[1]
local last_icon = proto.first_icon(cfg.BOSSES[last_boss].icon_from)
data:extend({
  {
    type = "technology",
    name = cfg.COMPLETE_TECH,
    localised_name = { "technology-name." .. cfg.COMPLETE_TECH },
    -- the description tells what the end of the trials opens: the warp drive, or nothing but the victory
    localised_description = { "technology-description." .. cfg.COMPLETE_TECH
      .. (settings.startup["nexus-bosses-gate-warp-drive"].value and "" or "-ungated") },
    icons = complete_icons(),
    essential = true,
    prerequisites = { cfg.CIRCLES[#cfg.CIRCLES].tech },
    research_trigger = {
      type = "scripted",
      trigger_description = { "nexus-bosses.trigger-circle-" .. #cfg.CIRCLES },
      icons = last_icon and { { icon = last_icon.icon, icon_size = last_icon.icon_size } } or nil,
    },
    order = "fa-b[nexus-trials]-z",
  },
})
