-- The expedition that came before the player: its wrecks (copies of the medium wrecks of the crash site, one log
-- each), the detector of the signal and the codex (shortcuts, available from the first stage on).

local util = require("util")
local cfg = require("lib.nb_data")

local prototypes = {}
for variant = 1, cfg.WRECK_VARIANTS do
  local wreck = util.table.deepcopy(data.raw.container["crash-site-spaceship-wreck-medium-" .. variant])
  wreck.name = cfg.WRECK_PREFIX .. variant
  wreck.localised_name = { "entity-name.nexus-expedition-wreck" }
  wreck.localised_description = { "entity-description.nexus-expedition-wreck" }
  wreck.minable = nil
  wreck.flags = { "placeable-neutral", "not-rotatable", "placeable-off-grid", "not-blueprintable", "not-deconstructable" }
  wreck.inventory_size = 1
  wreck.order = "z[nexus-expedition-wreck]-" .. variant
  prototypes[#prototypes + 1] = wreck
end

---A container of the story: a copy of a crash site container that can be opened, not mined or destroyed.
---@param source string
---@param name string
---@param slots integer
local function story_container(source, name, slots)
  local container = util.table.deepcopy(data.raw.container[source])
  container.name = name
  container.localised_name = { "entity-name." .. name }
  container.localised_description = { "entity-description." .. name }
  container.minable = nil
  container.flags = { "placeable-neutral", "not-rotatable", "placeable-off-grid", "not-blueprintable", "not-deconstructable" }
  container.inventory_size = slots
  container.order = "z[" .. name .. "]"
  return container
end
prototypes[#prototypes + 1] = story_container("crash-site-spaceship", cfg.CAMP, 8)
prototypes[#prototypes + 1] = story_container("crash-site-spaceship-wreck-big-1", cfg.LAST_STAND, 4)
prototypes[#prototypes + 1] = {
  type = "item",
  name = cfg.BADGE,
  icon = "__nexus-bosses__/graphics/icons/commander-badge.png",
  subgroup = data.raw["item-subgroup"]["omega-threat"] and "omega-threat" or "other",
  order = "y-e[nexus-commander-badge]",
  stack_size = 1,
  weight = 1000000,
}

local first_stage = cfg.CIRCLES[1].tech
prototypes[#prototypes + 1] = {
  type = "shortcut",
  name = cfg.SHORTCUT_DETECTOR,
  action = "lua",
  toggleable = true,
  icon = "__nexus-bosses__/graphics/shortcuts/detector-x56.png",
  icon_size = 56,
  small_icon = "__nexus-bosses__/graphics/shortcuts/detector-x24.png",
  small_icon_size = 24,
  technology_to_unlock = first_stage,
  unavailable_until_unlocked = true,
  order = "z[nexus-bosses]-a",
}
prototypes[#prototypes + 1] = {
  type = "shortcut",
  name = cfg.SHORTCUT_CODEX,
  action = "lua",
  icon = "__nexus-bosses__/graphics/shortcuts/codex-x56.png",
  icon_size = 56,
  small_icon = "__nexus-bosses__/graphics/shortcuts/codex-x24.png",
  small_icon_size = 24,
  technology_to_unlock = first_stage,
  unavailable_until_unlocked = true,
  order = "z[nexus-bosses]-b",
}
prototypes[#prototypes + 1] = {
  type = "sound",
  name = "nexus-bosses-detector",
  filename = "__nexus-bosses__/sounds/detector.ogg",
  volume = 0.6,
  category = "gui-effect",
}

data:extend(prototypes)
