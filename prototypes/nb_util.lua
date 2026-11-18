-- Helpers of the data stage.

local util = require("util")

local M = {}

---The item subgroup of the mod's items: Nexus-Threat makes "omega-threat" only while its startup setting
---nexus-threat-activation is on.
---@return string
function M.subgroup()
  return data.raw["item-subgroup"]["omega-threat"] and "omega-threat" or "other"
end

---Flags of the objects the script places in the world: neutral, fixed, not for blueprints or deconstruction.
---@return data.EntityPrototypeFlags
function M.world_flags()
  return { "placeable-neutral", "not-rotatable", "placeable-off-grid", "not-blueprintable", "not-deconstructable" }
end

---The first picture of a ruin of Fulgora.
---@param name string
---@return table
function M.ruin_picture(name)
  local ruin = data.raw["simple-entity"][name]
  local picture = util.table.deepcopy(ruin.pictures and ruin.pictures[1] or ruin.picture) --[[@as table]]
  picture["line_length"] = nil
  return picture
end

---The entity prototype of this name, whatever its type.
---@param name string
---@return table|nil
function M.find_entity(name)
  for type_name in pairs(defines.prototypes.entity) do
    local prototype = data.raw[type_name] and data.raw[type_name][name]
    if prototype then
      return prototype
    end
  end
  return nil
end

---The first icon layer of a prototype.
---@param prototype table
---@return {icon: string, icon_size: integer}
function M.icon_layer(prototype)
  if prototype.icon then
    return { icon = prototype.icon, icon_size = prototype.icon_size or 64 }
  end
  local first = prototype.icons[1]
  return { icon = first.icon, icon_size = first.icon_size or prototype.icon_size or 64 }
end

---The icon of an entity.
---@param name string
---@return {icon: string, icon_size: integer}
function M.entity_icon(name)
  return M.icon_layer(assert(M.find_entity(name), "nexus-bosses: no entity " .. name))
end

---Surface conditions of Nexus: the exact values of the planet, as the recipes of Nexus have them.
---@return table[]
function M.nexus_surface_conditions()
  local properties = data.raw.planet.nexus.surface_properties or {}
  local conditions = {}
  for _, property in ipairs({ "pressure", "gravity", "magnetic-field" }) do
    local value = properties[property]
    if value then
      conditions[#conditions + 1] = { property = property, min = value, max = value }
    end
  end
  return conditions
end

return M
