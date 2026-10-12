-- The entities of the active summon ("records" in summon.tracked):
--   required   the victory needs this one dead
--   role       "boss" | "escort" | "nest" | "guard"; the mod gives orders to "boss" and "escort" units
--   segmented  a LuaSegmentedUnit, not a LuaEntity
--   initial    health when it appeared: the full bar of the health display (Big Monsters spawns below the maximum)
--   hidden     the entity is gone for a while on purpose (the Devourer underground) and counts as alive
--   dead, gone a death event was seen / the object vanished without one

local M = {}

---@param summon table
---@param entity LuaEntity|LuaSegmentedUnit
---@param required boolean
---@param role string
---@param segmented boolean|nil
---@return table
function M.add(summon, entity, required, role, segmented)
  local record = {
    entity = entity,
    name = segmented and entity.prototype.name or entity.name, -- a LuaSegmentedUnit has no name
    unit_number = entity.unit_number,
    required = required,
    role = role,
    segmented = segmented or false,
    initial = entity.health,
    hidden = false,
    dead = false,
    gone = false,
  }
  summon.tracked[#summon.tracked + 1] = record
  summon.by_unit[record.unit_number] = record
  return record
end

---The record now follows another entity (the Devourer that surfaced again).
---@param summon table
---@param record table
---@param entity LuaEntity|LuaSegmentedUnit
function M.replace(summon, record, entity)
  summon.by_unit[record.unit_number] = nil
  record.entity = entity
  record.unit_number = entity.unit_number
  record.hidden = false
  summon.by_unit[record.unit_number] = record
end

---@param summon table
---@param unit_number integer
---@return table|nil the record, when it was alive
function M.mark_dead(summon, unit_number)
  local record = summon.by_unit[unit_number]
  if record and not record.dead then
    record.dead = true
    return record
  end
  return nil
end

---@param record table
---@return boolean
function M.alive(record)
  return not (record.dead or record.gone) and (record.hidden or record.entity.valid)
end

---Flags the records whose object vanished without a death event.
---@param summon table
function M.refresh(summon)
  for _, record in ipairs(summon.tracked) do
    if not (record.dead or record.gone or record.hidden or record.entity.valid) then
      record.gone = true
    end
  end
end

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

---Health of the required entities as a share of their health when they appeared.
---@param summon table
---@return number 0..1
function M.health_share(summon)
  local now, full = 0, 0
  for _, record in ipairs(summon.tracked) do
    if record.required then
      full = full + record.initial
      if record.hidden then
        now = now + (record.hidden_health or 0)
      elseif M.alive(record) then
        now = now + record.entity.health
      end
    end
  end
  if full <= 0 then
    return 0
  end
  return math.min(1, now / full)
end

---Living records of a role.
---@param summon table
---@param role string
---@return table[]
function M.of_role(summon, role)
  local list = {}
  for _, record in ipairs(summon.tracked) do
    if record.role == role and M.alive(record) and not record.hidden then
      list[#list + 1] = record
    end
  end
  return list
end

---Units the mod may give orders to.
---@param summon table
---@return LuaEntity[]
function M.commandable_units(summon)
  local units = {}
  for _, record in ipairs(summon.tracked) do
    if (record.role == "boss" or record.role == "escort") and not record.segmented and M.alive(record)
      and not record.hidden and record.entity.commandable then
      units[#units + 1] = record.entity
    end
  end
  return units
end

---The first living required entity: where the fight is.
---@param summon table
---@return table|nil
function M.main(summon)
  for _, record in ipairs(summon.tracked) do
    if record.required and M.alive(record) and not record.hidden then
      return record
    end
  end
  return nil
end

---@param record table
---@return MapPosition|nil
function M.position(record)
  if record.segmented then
    return record.entity.get_body_nodes()[1]
  end
  return record.entity.position
end

---Plain data for the remote interface.
---@param summon table
---@return table[]
function M.snapshot(summon)
  local list = {}
  for _, record in ipairs(summon.tracked) do
    local item = {
      name = record.name,
      unit_number = record.unit_number,
      required = record.required,
      role = record.role,
      segmented = record.segmented,
      hidden = record.hidden,
      dead = record.dead,
      gone = record.gone,
      initial = record.initial,
    }
    if M.alive(record) and not record.hidden then
      item.health = record.entity.health
      local position = M.position(record)
      if position then
        item.position = { x = position.x, y = position.y }
      end
    end
    list[#list + 1] = item
  end
  return list
end

return M
