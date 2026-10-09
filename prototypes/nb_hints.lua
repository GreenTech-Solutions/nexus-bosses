-- What a summon beacon tells about its boss: the damage it resists. Built from the prototypes at the end of the data
-- stage, so it follows whatever the other mods did to them, and handed to the description of the item and the entity
-- of the beacon as a localised string ("a bit of a puzzle with hints", the wish of the players).
--
--   Boss resistances (flat/percent):
--   Immune: Fire, Laser, Impact.
--   Resists: Physical 5/50%, Explosion 99%.
--   Weak to: Laser -200%, Fire -40%.
--   Regenerates about 3000 health per second.
--
-- Only the notable part is told: immune from 100 %, a resistance from cfg.HINT_MIN_PERCENT percent or a flat decrease of
-- cfg.HINT_MIN_FLAT, a weakness (a negative percent: the damage grows) from cfg.HINT_WEAK_PERCENT percent down. The
-- numbers follow the tooltips of the game: flat decrease first, then the percent. A boss that has several variants
-- (Big-Monsters picks one of them) is told by what all its variants share: a resistance is told by the least of the
-- variants, a weakness by the least negative one, and a damage type that one of them lacks counts as 0 %. The same
-- holds for a damage type that a prototype lists twice. A segmented unit (the Host Worm) is told by its body, which is
-- what the weapons hit.

local cfg = require("lib.nb_data")

local M = {}

-- the damage types of the game in the order of its tooltips, the others (mods) follow by name
local DAMAGE_ORDER = { "physical", "impact", "explosion", "fire", "laser", "electric", "poison", "acid", "cold" }
local DAMAGE_RANK = {}
for rank, name in ipairs(DAMAGE_ORDER) do
  DAMAGE_RANK[name] = rank
end

-- a localised string may hold at most 20 elements: longer lists are nested
local MAX_PARTS = 18

---@param parts any[] pieces of a concatenation
---@return data.LocalisedString
local function concat(parts)
  ---@type any[]
  local result = { "" }
  if #parts <= MAX_PARTS then
    for _, part in ipairs(parts) do
      result[#result + 1] = part
    end
    return result
  end
  local head = result
  for index = 1, MAX_PARTS - 1 do
    head[#head + 1] = parts[index]
  end
  local rest = {}
  for index = MAX_PARTS, #parts do
    rest[#rest + 1] = parts[index]
  end
  head[#head + 1] = concat(rest)
  return head
end

---Joins the items with commas into one concatenation. Every item is a list of parts (a damage type name and its value, for
---instance), which are spliced in flat: the nesting of localised strings stays shallow.
---@param items any[][]
---@return data.LocalisedString
local function join(items)
  local parts = {}
  for index, item in ipairs(items) do
    if index > 1 then
      parts[#parts + 1] = ", "
    end
    for _, part in ipairs(item) do
      parts[#parts + 1] = part
    end
  end
  return concat(parts)
end

---@param value number
---@return string
local function number_text(value)
  local text = string.format("%.1f", value)
  return (text:gsub("%.0$", ""))
end

---@param type_name string
---@return data.LocalisedString
local function damage_name(type_name)
  local damage = data.raw["damage-type"] and data.raw["damage-type"][type_name]
  return damage and damage.localised_name or { "damage-type-name." .. type_name }
end

---@class NbBounds
---@field low_percent number the least percent (what protects for sure)
---@field high_percent number the largest percent (what a weakness is sure to reach)
---@field low_flat number the least flat decrease

---The resistances of a prototype as {[damage type] = bounds}; a type that is listed twice gets the bounds of both entries.
---@param prototype table
---@return table<string, NbBounds>
local function resistances_of(prototype)
  ---@type table<string, NbBounds>
  local result = {}
  for _, resistance in ipairs(prototype.resistances or {}) do
    local percent = resistance.percent or 0
    local flat = resistance.decrease or 0
    local entry = result[resistance.type]
    if entry then
      entry.low_percent = math.min(entry.low_percent, percent)
      entry.high_percent = math.max(entry.high_percent, percent)
      entry.low_flat = math.min(entry.low_flat, flat)
    else
      result[resistance.type] = { low_percent = percent, high_percent = percent, low_flat = flat }
    end
  end
  return result
end

---What all the prototypes have in common (a type that one of them lacks counts as 0).
---@param prototypes table[]
---@return table<string, NbBounds>
local function common_resistances(prototypes)
  local maps = {}
  local types = {}
  for _, prototype in ipairs(prototypes) do
    local map = resistances_of(prototype)
    maps[#maps + 1] = map
    for type_name in pairs(map) do
      types[type_name] = true
    end
  end
  ---@type table<string, NbBounds>
  local common = {}
  for type_name in pairs(types) do
    local low_percent, high_percent, low_flat = math.huge, -math.huge, math.huge
    for _, map in ipairs(maps) do
      local entry = map[type_name] or { low_percent = 0, high_percent = 0, low_flat = 0 }
      low_percent = math.min(low_percent, entry.low_percent)
      high_percent = math.max(high_percent, entry.high_percent)
      low_flat = math.min(low_flat, entry.low_flat)
    end
    common[type_name] = { low_percent = low_percent, high_percent = high_percent, low_flat = low_flat }
  end
  return common
end

---@param list string[]
---@return string[] the damage types sorted by the order of the game
local function sorted_types(list)
  table.sort(list, function(a, b)
    local rank_a = DAMAGE_RANK[a] or (#DAMAGE_ORDER + 1)
    local rank_b = DAMAGE_RANK[b] or (#DAMAGE_ORDER + 1)
    if rank_a ~= rank_b then
      return rank_a < rank_b
    end
    return a < b
  end)
  return list
end

---The prototypes whose resistances a boss is told by, and whether the boss has several variants of which the event picks
---one.
---@param id string boss id
---@return table[] found the prototypes, none when they do not exist
---@return boolean variants
local function sources_of(id)
  local boss = cfg.BOSSES[id]
  local found = {}
  if boss.kind == "bm" then
    local set = cfg.BM_SETS[id]
    for _, name in ipairs(set.hint_names) do
      for _, type_name in ipairs(set.types) do
        local prototype = data.raw[type_name] and data.raw[type_name][name]
        if prototype then
          found[#found + 1] = prototype
          break
        end
      end
    end
    if #found == 0 then
      -- Big-Monsters changed its names: everything it has of this kind
      for _, type_name in ipairs(set.types) do
        for name, prototype in pairs(data.raw[type_name] or {}) do
          for _, prefix in ipairs(set.prefixes) do
            if name:sub(1, #prefix) == prefix then
              found[#found + 1] = prototype
              break
            end
          end
        end
      end
    end
    return found, #found > 1
  end
  for _, candidate in ipairs(boss.hint_from or {}) do
    local group = data.raw[candidate[1]]
    local prototype = group and group[candidate[2]]
    if prototype then
      if prototype.type == "segmented-unit" and prototype.segment_engine then
        -- the body: the distinct segment prototypes
        local seen = {}
        for _, entry in ipairs(prototype.segment_engine.segments or {}) do
          local segment = data.raw["segment"] and data.raw["segment"][entry.segment]
          if segment and not seen[segment.name] then
            seen[segment.name] = true
            found[#found + 1] = segment
          end
        end
      end
      if #found == 0 then
        found[1] = prototype
      end
      return found, false
    end
  end
  return found, false
end

---Health regenerated per second by the boss (0 when it is not told).
---@param id string
---@return number
local function regeneration_of(id)
  local boss = cfg.BOSSES[id]
  if boss.kind ~= "own" then
    return 0
  end
  for _, candidate in ipairs(boss.hint_from or {}) do
    local group = data.raw[candidate[1]]
    local prototype = group and group[candidate[2]]
    if prototype then
      return (prototype.healing_per_tick or 0) * 60
    end
  end
  return 0
end

---Health of a boss the mod spawns itself, as it is on Nexus (0 when it is not told). The health of a spawner grows with
---the evolution of the surface (see prototypes/nb_enemies.lua), so the Toxic Lair is told at the evolution of Nexus.
---@param id string
---@return number
local function health_of(id)
  local boss = cfg.BOSSES[id]
  if boss.kind ~= "own" then
    return 0
  end
  for _, candidate in ipairs(boss.hint_from or {}) do
    local group = data.raw[candidate[1]]
    local prototype = group and group[candidate[2]]
    if prototype then
      local health = prototype.max_health or 0
      if prototype.type == "unit-spawner" then
        local constants = data.raw["utility-constants"] and data.raw["utility-constants"].default
        health = health * (constants and constants.spawner_evolution_factor_health_modifier or 10) ^ cfg.EVOLUTION
      end
      return health
    end
  end
  return 0
end

---The hint of a boss, or nil when the prototypes are not there.
---@param id string boss id
---@return data.LocalisedString|nil
function M.hint(id)
  local sources, variants = sources_of(id)
  if #sources == 0 then
    return nil
  end
  local common = common_resistances(sources)

  local immune, resists, weak = {}, {}, {}
  local names = {}
  for type_name in pairs(common) do
    names[#names + 1] = type_name
  end
  for _, type_name in ipairs(sorted_types(names)) do
    local entry = common[type_name]
    local percent, flat = entry.low_percent, entry.low_flat
    if percent >= 100 then
      immune[#immune + 1] = { damage_name(type_name) }
    elseif percent >= cfg.HINT_MIN_PERCENT or (flat >= cfg.HINT_MIN_FLAT and percent > cfg.HINT_WEAK_PERCENT) then
      local value = number_text(percent) .. "%"
      if flat > 0 then
        value = number_text(flat) .. "/" .. value
      end
      resists[#resists + 1] = { type = type_name, value = value, name = damage_name(type_name) }
    elseif entry.high_percent <= cfg.HINT_WEAK_PERCENT then
      weak[#weak + 1] = { damage_name(type_name), " " .. number_text(entry.high_percent) .. "%" }
    end
  end

  -- six or more types with the very same value: "most other types 35%"
  local by_value = {}
  local values = {}
  for _, item in ipairs(resists) do
    if not by_value[item.value] then
      by_value[item.value] = 0
      values[#values + 1] = item.value
    end
    by_value[item.value] = by_value[item.value] + 1
  end
  table.sort(values, function(a, b)
    if by_value[a] ~= by_value[b] then
      return by_value[a] > by_value[b]
    end
    return a < b
  end)
  local grouped_value = values[1] and by_value[values[1]] >= 6 and values[1] or nil
  local resist_items = {}
  for _, item in ipairs(resists) do
    if item.value ~= grouped_value then
      resist_items[#resist_items + 1] = { item.name, " " .. item.value }
    end
  end
  if grouped_value then
    resist_items[#resist_items + 1] = { { "nexus-bosses.hint-most", grouped_value } }
  end

  local lines = {}
  if #immune > 0 then
    lines[#lines + 1] = { "nexus-bosses.hint-immune", join(immune) }
  end
  if #resist_items > 0 then
    lines[#lines + 1] = { "nexus-bosses.hint-resists", join(resist_items) }
  end
  if #weak > 0 then
    lines[#lines + 1] = { "nexus-bosses.hint-weak", join(weak) }
  end
  if #lines == 0 then
    lines[1] = { "nexus-bosses.hint-none" }
  end
  local health = health_of(id)
  if health > 0 then
    -- rounded to thousands: the health of a spawner comes out of a power and is not a round number
    table.insert(lines, 1, { "nexus-bosses.hint-health", number_text(math.floor(health / 1000 + 0.5) * 1000) })
  end
  local regeneration = regeneration_of(id)
  if regeneration >= cfg.HINT_MIN_REGEN then
    lines[#lines + 1] = { "nexus-bosses.hint-regen", number_text(math.floor(regeneration)) }
  end

  ---@type any[]
  local parts = { { variants and "nexus-bosses.hint-header-variants" or "nexus-bosses.hint-header" } }
  for _, line in ipairs(lines) do
    parts[#parts + 1] = "\n"
    parts[#parts + 1] = line
  end
  return concat(parts)
end

return M
