-- Weak and strong damage types of an entity prototype, from its resistance shares (0..1). Only the types a player
-- deals with turrets and weapons count: mods add their own types with odd values (rabbasca-psychic -438100 %).

local TYPES = { "physical", "impact", "fire", "acid", "poison", "explosion", "laser", "electric" }
local WEAK_BELOW = 0.3
local STRONG_FROM = 0.6
local TYPE_ORDER = {}
for index, damage_type in ipairs(TYPES) do
  TYPE_ORDER[damage_type] = index
end

local M = {}

---@type table<string, {weak: string[], strong: string[]}>
local cache = {}

---@param entity_name string
---@return string[] damage types with the lowest share when it is < WEAK_BELOW, in type order
---@return string[] strong damage types with share >= STRONG_FROM, highest first
function M.of(entity_name)
  local cached = cache[entity_name]
  if cached then
    return cached.weak, cached.strong
  end

  local prototype = prototypes.entity[entity_name]
  local shares = {}
  local lowest_share
  local all_equal = true
  local first_share
  ---@type {name: string, share: number}[]
  local strong_entries = {}
  local resistances = prototype and prototype.resistances or {}
  for _, damage_type in ipairs(TYPES) do
    local resistance = resistances[damage_type]
    local share = resistance and resistance.percent or 0
    shares[damage_type] = share
    if first_share == nil then
      first_share = share
    elseif share ~= first_share then
      all_equal = false
    end
    if lowest_share == nil or share < lowest_share then
      lowest_share = share
    end
    if share >= STRONG_FROM then
      strong_entries[#strong_entries + 1] = { name = damage_type, share = share }
    end
  end

  ---@type {name: string, share: number}[]
  local weak_entries = {}
  if not all_equal and lowest_share and lowest_share < WEAK_BELOW then
    for _, damage_type in ipairs(TYPES) do
      if shares[damage_type] == lowest_share then
        weak_entries[#weak_entries + 1] = { name = damage_type, share = lowest_share }
      end
    end
  end
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
