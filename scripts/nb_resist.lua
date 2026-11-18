-- Weak and strong damage types of an entity prototype, from its resistance shares (0..1). Only the types a player
-- deals with turrets and weapons count: mods add their own types with odd values (rabbasca-psychic -438100 %).

local TYPES = { "physical", "impact", "fire", "acid", "poison", "explosion", "laser", "electric" }
local WEAK_BELOW = 0
local STRONG_FROM = 0.6
local TYPE_ORDER = {}
local TYPE_SET = {}
for index, damage_type in ipairs(TYPES) do
  TYPE_ORDER[damage_type] = index
  TYPE_SET[damage_type] = true
end

local M = {}

---@type table<string, {weak: string[], strong: string[]}>
local cache = {}

---@param entity_name string
---@return string[] weak damage types with share < WEAK_BELOW, lowest first
---@return string[] strong damage types with share >= STRONG_FROM, highest first
function M.of(entity_name)
  local cached = cache[entity_name]
  if cached then
    return cached.weak, cached.strong
  end

  ---@type {name: string, share: number}[]
  local weak_entries = {}
  ---@type {name: string, share: number}[]
  local strong_entries = {}
  local prototype = prototypes.entity[entity_name]
  for damage_type, resistance in pairs(prototype and prototype.resistances or {}) do
    if TYPE_SET[damage_type] then
      local share = resistance.percent or 0
      if share < WEAK_BELOW then
        weak_entries[#weak_entries + 1] = { name = damage_type, share = share }
      elseif share >= STRONG_FROM then
        strong_entries[#strong_entries + 1] = { name = damage_type, share = share }
      end
    end
  end

  table.sort(weak_entries, function(a, b)
    if a.share ~= b.share then
      return a.share < b.share
    end
    return TYPE_ORDER[a.name] < TYPE_ORDER[b.name]
  end)
  table.sort(strong_entries, function(a, b)
    if a.share ~= b.share then
      return a.share > b.share
    end
    return TYPE_ORDER[a.name] < TYPE_ORDER[b.name]
  end)

  ---@type string[]
  local weak = {}
  for _, entry in ipairs(weak_entries) do
    weak[#weak + 1] = entry.name
  end
  ---@type string[]
  local strong = {}
  for _, entry in ipairs(strong_entries) do
    strong[#strong + 1] = entry.name
  end

  cache[entity_name] = { weak = weak, strong = strong }
  return weak, strong
end

---@param damage_types string[]
---@return LocalisedString
function M.list_caption(damage_types)
  if #damage_types == 0 then
    return { "nexus-bosses.bar-resist-none" }
  end
  ---@type LocalisedString[]
  local caption = { "" }
  for index, damage_type in ipairs(damage_types) do
    if index > 1 then
      caption[#caption + 1] = ", "
    end
    caption[#caption + 1] = { "damage-type-name." .. damage_type }
  end
  return caption --[[@as LocalisedString]]
end

---@param entity_name string
---@return LocalisedString
function M.caption(entity_name)
  local weak, strong = M.of(entity_name)
  return { "nexus-bosses.bar-resist", M.list_caption(weak), M.list_caption(strong) }
end

return M
