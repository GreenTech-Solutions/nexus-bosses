-- The entities of the active summon that the mod watches ("records" in summon.tracked).
-- A record is {entity, name, unit_number, required, role, segmented, dead, gone}:
--   required   the victory needs this one dead
--   role       "boss" | "escort" | "guard" (informational, the mod commands "boss" and "escort" units)
--   segmented  the entity is a LuaSegmentedUnit, not a LuaEntity
--   dead       a death event was seen
--   gone       the object vanished without a death event (destroyed by a script, the game, another mod)

local M = {}

---@param summon table
---@param entity LuaEntity|LuaSegmentedUnit
---@param name string
---@param required boolean
---@param role string
---@param segmented boolean|nil
---@return table the record
function M.add(summon, entity, name, required, role, segmented)
  local record = {
    entity = entity,
    name = name,
    unit_number = entity.unit_number,
    required = required,
    role = role,
    segmented = segmented or false,
    dead = false,
    gone = false,
  }
  summon.tracked[#summon.tracked + 1] = record
  if record.unit_number then
    summon.by_unit[record.unit_number] = record
  end
  return record
end

---Marks the record of a dead entity.
---@param summon table
---@param unit_number integer
---@return table|nil the record when it was found and not dead yet
function M.mark_dead(summon, unit_number)
  local record = summon.by_unit[unit_number]
  if record and not record.dead then
    record.dead = true
    return record
  end
  return nil
end

---Flags the records whose object is gone without a death event.
---@param summon table
function M.refresh(summon)
  for _, record in ipairs(summon.tracked) do
    if not record.dead and not record.gone and not (record.entity and record.entity.valid) then
      record.gone = true
    end
  end
end

---Counts of the required records: still alive, dead, gone.
---@param summon table
---@return integer alive
---@return integer dead
---@return integer gone
function M.status(summon)
  local alive, dead, gone = 0, 0, 0
  for _, record in ipairs(summon.tracked) do
    if record.required then
      if record.dead then
        dead = dead + 1
      elseif record.gone then
        gone = gone + 1
      else
        alive = alive + 1
      end
    end
  end
  return alive, dead, gone
end

---Valid living unit entities the mod may give orders to (not segmented units, not required-only spawners).
---@param summon table
---@return LuaEntity[]
function M.commandable_units(summon)
  local units = {}
  for _, record in ipairs(summon.tracked) do
    local entity = record.entity
    if not (record.dead or record.gone or record.segmented) and entity.valid and entity.commandable
      and (record.role == "boss" or record.role == "escort") then
      units[#units + 1] = entity
    end
  end
  return units
end

---Plain data of the records for the remote interface.
---@param summon table
---@return table[]
function M.snapshot(summon)
  local list = {}
  for _, record in ipairs(summon.tracked) do
    local entity = record.entity
    local valid = entity ~= nil and entity.valid
    local item = {
      name = record.name,
      unit_number = record.unit_number,
      required = record.required,
      role = record.role,
      segmented = record.segmented,
      dead = record.dead,
      gone = record.gone,
      valid = valid,
    }
    if valid then
      item.health = entity.health
      if record.segmented then
        local head = entity.get_body_nodes()[1]
        if head then
          item.position = { x = head.x, y = head.y }
        end
      else
        item.position = { x = entity.position.x, y = entity.position.y }
      end
    end
    list[#list + 1] = item
  end
  return list
end

return M
