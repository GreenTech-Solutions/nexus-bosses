-- The stages of the signal of Nexus and the silence after them. No science cost, only triggers.
--   nexus-whisper      researched by building a shield stabilizer. The stabilizer exists only while the startup setting
--                      nexus-threat-activation of Nexus-Threat is on; without it the trigger is scripted and
--                      scripts/nb_progress.lua researches the stage once planet-discovery-nexus is researched
--   nexus-chorus,      scripted: researched when the three bosses of the previous stage are dead. Each one also
--   nexus-convergence  sharpens the weapons the next stage needs
--   nexus-silence      crafting the warp key (one trophy of each boss); it opens the routes of the warp drive
--                      (prototypes/nb_nexus.lua). Not made when the startup setting nexus-bosses-gate-warp-drive is off

local cfg = require("lib.nb_data")
local proto = require("prototypes.nb_util")
local nexus = require("prototypes.nb_nexus")

local GATED = settings.startup["nexus-bosses-gate-warp-drive"].value
local base_icon = proto.icon_layer(data.raw.technology[cfg.PLANET_TECH])

---The technology of Nexus with an icon in the lower right corner.
---@param corner {icon: string, icon_size: integer}
local function icons(corner)
  return {
    { icon = base_icon.icon, icon_size = base_icon.icon_size },
    { icon = corner.icon, icon_size = corner.icon_size, scale = 64 / corner.icon_size, shift = { 30, 30 }, draw_background = true },
  }
end

---Damage bonuses that exist in this game.
---@param categories string[]
---@param modifier number
local function damage_bonus(categories, modifier)
  local effects = {}
  for _, category in ipairs(categories) do
    if data.raw["ammo-category"][category] then
      effects[#effects + 1] = { type = "ammo-damage", ammo_category = category, modifier = modifier }
    end
  end
  return effects
end

-- what beating a stage gives on top of the next beacons: the Chorus is weak to energy weapons, the Convergence shrugs
-- them off
local BONUSES = {
  [2] = damage_bonus({ "laser", "tesla", "electric" }, 0.2),
  [3] = damage_bonus({ "bullet", "railgun", "rocket", "cannon-shell" }, 0.2),
}

local stabilizer = data.raw.item["shield-stabilizer"]
local stabilizer_entity = stabilizer and stabilizer.place_result

for index, circle in ipairs(cfg.CIRCLES) do
  local effects = {}
  for _, id in ipairs(circle.bosses) do
    effects[#effects + 1] = { type = "unlock-recipe", recipe = cfg.beacon_name(id) }
  end
  for _, bonus in ipairs(BONUSES[index] or {}) do
    effects[#effects + 1] = bonus
  end
  if index == #cfg.CIRCLES and GATED then
    effects[#effects + 1] = { type = "unlock-recipe", recipe = cfg.WARP_KEY }
  end

  local trigger
  local description = { "technology-description." .. circle.tech }
  if index == 1 and stabilizer_entity then
    trigger = { type = "build-entity", entity = stabilizer_entity }
  elseif index == 1 then
    trigger = { type = "scripted", trigger_description = { "nexus-bosses.trigger-start" } }
    description = { "technology-description." .. circle.tech .. "-scripted" }
  else
    trigger = {
      type = "scripted",
      trigger_description = { "nexus-bosses.trigger-stage", { "nexus-bosses.stage-" .. cfg.CIRCLES[index - 1].stage } },
    }
  end

  data:extend({
    {
      type = "technology",
      name = circle.tech,
      localised_description = description,
      icons = icons(proto.entity_icon(cfg.BOSSES[circle.bosses[1]].entity)),
      essential = true,
      prerequisites = { index == 1 and cfg.PLANET_TECH or cfg.CIRCLES[index - 1].tech },
      research_trigger = trigger,
      effects = effects,
      order = "fa-b[nexus-signal]-" .. index,
    },
  })
end

if GATED then
  data:extend({
    {
      type = "technology",
      name = cfg.SILENCE_TECH,
      icons = icons({ icon = "__nexus-bosses__/graphics/icons/warp-key.png", icon_size = 64 }),
      essential = true,
      prerequisites = { cfg.CIRCLES[#cfg.CIRCLES].tech },
      research_trigger = { type = "craft-item", item = cfg.WARP_KEY },
      effects = nexus.routes,
      order = "fa-b[nexus-signal]-z",
    },
  })
end
