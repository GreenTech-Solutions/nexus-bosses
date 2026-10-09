-- Helpers of the data stage.

local M = {}

---Prototype by name among the given types.
---@param name string
---@param types string[]
---@return table|nil
function M.find_prototype(name, types)
  for _, type_name in ipairs(types) do
    local group = data.raw[type_name]
    local prototype = group and group[name]
    if prototype then
      return prototype
    end
  end
  return nil
end

---The entity prototype of this name, whatever its type is (entity names are unique across the entity types).
---@param name string
---@return table|nil
function M.find_entity(name)
  for type_name in pairs(defines.prototypes.entity) do
    local group = data.raw[type_name]
    local prototype = group and group[name]
    if prototype then
      return prototype
    end
  end
  return nil
end

---The first icon layer of a prototype as {icon, icon_size}.
---@param prototype table|nil
---@return {icon: string, icon_size: integer}|nil
function M.icon_layer(prototype)
  if not prototype then
    return nil
  end
  if prototype.icon then
    return { icon = prototype.icon, icon_size = prototype.icon_size or 64 }
  end
  local first = prototype.icons and prototype.icons[1]
  if first and first.icon then
    return { icon = first.icon, icon_size = first.icon_size or prototype.icon_size or 64 }
  end
  return nil
end

---The icon of the first existing prototype among the candidates {type, name}.
---@param candidates string[][]
---@return {icon: string, icon_size: integer}|nil
function M.first_icon(candidates)
  for _, candidate in ipairs(candidates) do
    local layer = M.icon_layer(M.find_prototype(candidate[2], { candidate[1] }))
    if layer then
      return layer
    end
  end
  return nil
end

---Surface conditions of Nexus: exactly the values of the planet, like the recipes of Nexus have them.
---@return table[]
function M.nexus_surface_conditions()
  local planet = data.raw.planet and data.raw.planet.nexus
  local properties = planet and planet.surface_properties or {}
  local defaults = { pressure = 10000, gravity = 180, ["magnetic-field"] = 120 }
  local conditions = {}
  for _, property in ipairs({ "pressure", "gravity", "magnetic-field" }) do
    local value = properties[property] or defaults[property]
    conditions[#conditions + 1] = { property = property, min = value, max = value }
  end
  return conditions
end

return M
