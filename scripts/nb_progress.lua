-- Progress of the trials per force: storage.progress[force_name] = { defeated = { [boss_id] = true } }.
-- The three bosses of a stage research the next stage; every victory drops a trophy where the boss fell; the warp key
-- (one trophy of each boss) researches nexus-silence by the crafting trigger of the game.

local cfg = require("lib.nb_data")
local util = require("scripts.nb_util")

local M = {}

---@param force_name string
---@return {defeated: table<string, boolean>}
local function record_of(force_name)
  local record = storage.progress[force_name]
  if not record then
    record = { defeated = {} }
    storage.progress[force_name] = record
  end
  return record
end

---@param force_name string
---@param boss_id string
---@return boolean
function M.is_defeated(force_name, boss_id)
  ---@type {defeated: table<string, boolean>}|nil
  local record = storage.progress[force_name]
  return record ~= nil and record.defeated[boss_id] == true
end

---@param force_name string
---@param circle_index integer
---@return boolean
function M.circle_done(force_name, circle_index)
  local record = storage.progress[force_name]
  if not record then
    return false
  end
  for _, boss_id in ipairs(cfg.CIRCLES[circle_index].bosses) do
    if not record.defeated[boss_id] then
      return false
    end
  end
  return true
end

---Researches a technology with a scripted trigger.
---@param force LuaForce
---@param tech_name string
---@return boolean true when this call researched it
function M.research(force, tech_name)
  local technology = force.technologies[tech_name]
  if technology.researched then
    return false
  end
  force.script_trigger_research(tech_name)
  if not technology.researched then
    -- the trigger does not fire while the prerequisites are not researched (an old save, a reset)
    technology.researched = true
  end
  return true
end

---@return boolean the first circle has a scripted trigger (no shield stabilizer in this game)
local function first_circle_is_scripted()
  local trigger = prototypes.technology[cfg.CIRCLES[1].tech].research_trigger --[[@as ResearchTrigger]]
  return trigger.type == "scripted"
end

---Opens the first circle when its trigger is scripted and Nexus is discovered.
---@param force LuaForce
function M.sync_first_circle(force)
  if first_circle_is_scripted() and force.technologies[cfg.PLANET_TECH].researched then
    M.research(force, cfg.CIRCLES[1].tech)
  end
end

---Opens the first circle when a shield stabilizer of the force already stands on Nexus: a game that built one before
---this mod was added never fires the build trigger.
---@param force LuaForce
function M.sync_built_stabilizer(force)
  local surface = util.nexus()
  if first_circle_is_scripted() or not surface or force.technologies[cfg.CIRCLES[1].tech].researched then
    return
  end
  local stabilizer = prototypes.item["shield-stabilizer"].place_result --[[@as LuaEntityPrototype]]
  if surface.count_entities_filtered({ name = stabilizer.name, force = force, limit = 1 }) > 0 then
    M.research(force, cfg.CIRCLES[1].tech)
  end
end

---@param technology LuaTechnology
function M.on_research_finished(technology)
  local force = technology.force
  if technology.name == cfg.PLANET_TECH then
    M.sync_first_circle(force)
  elseif technology.name == cfg.SILENCE_TECH then
    util.say(force, { "nexus-bosses.msg-silence" }, util.COLORS.good)
    util.play(force, "silence")
  end
end

---Researches the next stage for every finished one that has not opened it yet.
---@param force LuaForce
---@param announce boolean
function M.sync_unlocks(force, announce)
  for index, circle in ipairs(cfg.CIRCLES) do
    if M.circle_done(force.name, index) then
      if circle.reward and M.research(force, circle.reward) and announce then
        util.say(force, { "nexus-bosses.msg-stage-done-" .. circle.stage }, util.COLORS.good)
        util.play(force, "stage-complete")
      elseif not circle.reward and announce then
        local silence = force.technologies[cfg.SILENCE_TECH]
        if not silence then
          util.say(force, { "nexus-bosses.msg-stage-done-" .. circle.stage .. "-ungated" }, util.COLORS.good)
        elseif not silence.researched then
          util.say(force, { "nexus-bosses.msg-stage-done-" .. circle.stage }, util.COLORS.good)
          util.play(force, "stage-complete")
        end
      end
    end
  end
end

---@param force LuaForce
---@param boss_id string
---@return boolean true for the first victory over this boss
function M.mark_defeated(force, boss_id)
  local record = record_of(force.name)
  local first = not record.defeated[boss_id]
  record.defeated[boss_id] = true
  return first
end

---The trophy of the boss falls where the boss fell, marked on the map.
---@param force LuaForce
---@param surface LuaSurface
---@param boss_id string
---@param position MapPosition
---@param quality string|nil the second trophy of a fight in the lair
function M.drop_trophy(force, surface, boss_id, position, quality)
  local stack = { name = cfg.trophy_name(boss_id), count = 1, quality = quality }
  local spilled = surface.spill_item_stack({ position = position, stack = stack, enable_looted = true, allow_belts = false })
  local where = spilled[1] and spilled[1].position or position
  force.add_chart_tag(surface, { position = where, icon = { type = "item", name = stack.name, quality = quality } })
  local x, y = util.xy(where)
  util.play(force, "trophy")
  local item = string.format("[item=%s,quality=%s]", stack.name, quality or "normal")
  util.say(force, { "nexus-bosses.msg-trophy", { "", item, " ", { "item-name." .. stack.name } }, math.floor(x), math.floor(y),
    surface.name }, util.COLORS.good)
end

---After the Storm Guardian falls the storms stay weaker for good (the multiplier lives in Nexus-Threat; without its
---interface the flag waits for it and the call is repeated when the configuration changes).
---@return boolean applied
function M.apply_storm_multiplier()
  if not storage.storm_weakened then
    return true
  end
  local interface = remote.interfaces["nexus-threat"]
  if not (interface and interface.set_storm_multiplier) then
    return false
  end
  return (pcall(function()
    remote.call("nexus-threat", "set_storm_multiplier", cfg.STORM_MULTIPLIER)
  end))
end

---@param force LuaForce
function M.storm_guardian_fell(force)
  storage.storm_weakened = true
  if M.apply_storm_multiplier() then
    util.say(force, { "nexus-bosses.msg-storm-weakened" }, util.COLORS.good)
  end
end

---@param source_name string
---@param destination LuaForce
function M.on_forces_merged(source_name, destination)
  local source = storage.progress[source_name]
  if source then
    local target = record_of(destination.name)
    for boss_id in pairs(source.defeated) do
      target.defeated[boss_id] = true
    end
    M.sync_unlocks(destination, false)
  end
  storage.progress[source_name] = nil
end

function M.on_configuration_changed()
  for force_name, record in pairs(storage.progress) do
    -- bosses of an older version of the mod
    for boss_id in pairs(record.defeated) do
      if not cfg.BOSSES[boss_id] then
        record.defeated[boss_id] = nil
      end
    end
    local force = game.forces[force_name]
    if force then
      M.sync_unlocks(force, false)
    end
  end
  for _, force in pairs(game.forces) do
    if force.name ~= "enemy" and force.name ~= "neutral" then
      M.sync_first_circle(force)
      M.sync_built_stabilizer(force)
    end
  end
  M.apply_storm_multiplier()
end

return M
