-- Progress of the trials per force: which bosses are beaten, which circles are done, and what it opens.
-- storage.progress[force_name] = { defeated = { [boss_id] = true } }

local cfg = require("lib.nb_data")
local util = require("scripts.nb_util")

local M = {}

---@class NbForceProgress
---@field defeated table<string, boolean>

---@param force_name string
---@return NbForceProgress
local function record_of(force_name)
  ---@type NbForceProgress|nil
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
  ---@type NbForceProgress|nil
  local record = storage.progress[force_name]
  return record ~= nil and record.defeated[boss_id] == true
end

---@param force_name string
---@param circle_index integer
---@return boolean all three bosses of the circle are beaten
function M.circle_done(force_name, circle_index)
  ---@type NbForceProgress|nil
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

---Researches a technology with a scripted trigger for the force. Setting `researched` is the fallback for a
---technology whose trigger the game would not fire (its prerequisites are not researched, for instance).
---@param force LuaForce
---@param tech_name string
---@return boolean true when the technology was researched by this call
local function research(force, tech_name)
  local technology = force.technologies[tech_name]
  if not technology or technology.researched then
    return false
  end
  force.script_trigger_research(tech_name)
  if not technology.researched then
    technology.researched = true
  end
  return technology.researched == true
end

---True when the first circle has a scripted trigger: Nexus-Threat is switched off, so there is no shield stabilizer to
---build and the script has to open the circle (see prototypes/nb_technologies.lua).
---@return boolean
local function first_circle_is_scripted()
  local technology = prototypes.technology[cfg.CIRCLES[1].tech]
  local trigger = technology and technology.research_trigger
  return trigger ~= nil and trigger.type == "scripted"
end

---Researches the first circle for the force when its trigger is scripted and Nexus is discovered.
---@param force LuaForce
---@return boolean true when the circle was researched by this call
function M.sync_first_circle(force)
  if not first_circle_is_scripted() then
    return false
  end
  local discovered = force.technologies[cfg.PLANET_TECH]
  if not (discovered and discovered.researched) then
    return false
  end
  return research(force, cfg.CIRCLES[1].tech)
end

---Researches the first circle for the force when a shield stabilizer of the force stands on Nexus already: a game that
---built one before this mod was added never fires the build trigger of the circle.
---@param force LuaForce
---@return boolean true when the circle was researched by this call
function M.sync_built_stabilizer(force)
  if first_circle_is_scripted() then
    return false
  end
  local technology = force.technologies[cfg.CIRCLES[1].tech]
  if not technology or technology.researched then
    return false
  end
  local surface = util.nexus()
  if not surface then
    return false
  end
  local names = {}
  for name in pairs(prototypes.get_entity_filtered({ { filter = "type", type = "assembling-machine" } })) do
    if name:find("^shield%-stabilizer%-") then
      names[#names + 1] = name
    end
  end
  if #names == 0 or surface.count_entities_filtered({ name = names, force = force, limit = 1 }) == 0 then
    return false
  end
  return research(force, cfg.CIRCLES[1].tech)
end

---A technology was researched: the discovery of Nexus opens the first circle when there is no stabilizer to build.
---@param technology LuaTechnology
function M.on_research_finished(technology)
  if technology and technology.valid and technology.name == cfg.PLANET_TECH then
    M.sync_first_circle(technology.force)
  end
end

---Marks the boss as beaten for the force.
---@param force LuaForce
---@param boss_id string
---@return boolean true for the first victory over this boss
function M.mark_defeated(force, boss_id)
  local record = record_of(force.name)
  local first = not record.defeated[boss_id]
  record.defeated[boss_id] = true
  return first
end

---Researches the reward technology of every finished circle that is not researched yet.
---@param force LuaForce
---@param announce boolean print a message for every circle opened by this call
---@return integer[] the finished circles that opened something
function M.sync_unlocks(force, announce)
  local opened = {}
  for index, circle in ipairs(cfg.CIRCLES) do
    if M.circle_done(force.name, index) and research(force, circle.reward) then
      opened[#opened + 1] = index
      if announce then
        if circle.reward == cfg.COMPLETE_TECH then
          local gated = settings.startup["nexus-bosses-gate-warp-drive"].value
          util.say(force, { gated and "nexus-bosses.msg-trials-complete" or "nexus-bosses.msg-trials-complete-ungated" },
            util.COLORS.good)
        else
          util.say(force, { "nexus-bosses.msg-circle-complete", cfg.ROMAN[index], { "technology-name." .. circle.reward } },
            util.COLORS.good)
        end
      end
    end
  end
  return opened
end

---After the Storm Guardian falls the storms stay weaker for good. The multiplier lives in Nexus-Threat; if its
---interface is missing (Nexus-Threat replaced or its activation switched off) the flag stays and the call is
---repeated when the configuration changes.
---@return boolean true when the multiplier was applied
function M.apply_storm_multiplier()
  if not storage.storm_weakened then
    return true
  end
  local interface = remote.interfaces["nexus-threat"]
  if not (interface and interface.set_storm_multiplier) then
    return false
  end
  local ok = pcall(function()
    remote.call("nexus-threat", "set_storm_multiplier", cfg.STORM_MULTIPLIER)
  end)
  return ok
end

---The victory over the Storm Guardian.
---@param force LuaForce
function M.storm_guardian_fell(force)
  storage.storm_weakened = true
  if M.apply_storm_multiplier() then
    util.say(force, { "nexus-bosses.msg-storm-weakened", cfg.STORM_MULTIPLIER }, util.COLORS.good)
  else
    util.say(force, { "nexus-bosses.msg-storm-unavailable" }, util.COLORS.warning)
  end
end

---Two forces became one: the destination keeps every victory of both.
---@param source_name string
---@param destination LuaForce
function M.on_forces_merged(source_name, destination)
  local source = storage.progress[source_name]
  if source and destination and destination.valid then
    local target = record_of(destination.name)
    for boss_id in pairs(source.defeated) do
      target.defeated[boss_id] = true
    end
    M.sync_unlocks(destination, false)
  end
  storage.progress[source_name] = nil
end

---The configuration changed: technologies may have been reset, Nexus-Threat may have appeared.
function M.on_configuration_changed()
  for force_name in pairs(storage.progress) do
    local force = game.forces[force_name]
    if force and force.valid then
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
