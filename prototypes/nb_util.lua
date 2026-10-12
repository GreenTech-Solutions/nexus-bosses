-- Helpers of the data stage.

local M = {}

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
