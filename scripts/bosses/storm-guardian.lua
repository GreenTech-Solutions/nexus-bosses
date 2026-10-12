-- Storm Guardian: a walking electric giant with 20 walkers and 20 flyers. While a storm of Nexus-Threat rages it feeds
-- on it: it heals 0.5 % of its health every second and calls lightning down around itself. Between the storms it is
-- only a very big target. Without Nexus-Threat's storms (its startup setting nexus-threat-activation off) it never
-- feeds.

local cfg = require("lib.nb_data")
local util = require("scripts.nb_util")
local records = require("scripts.nb_records")
local spawn = require("scripts.nb_spawn")

local M = {}

local WALKER = "walking-electric-unit-5"
local FLYER = "flying-electric-unit-5"
local ESCORTS = 20
local ESCORT_RADIUS = 20
local HEAL_SHARE = 0.005
local LIGHTNING_SECONDS = 3
local FEED_SOUND_SECONDS = 6
local LIGHTNING_RADIUS = 12
local REDISPATCH_SECONDS = 45

---@return boolean
local function storm_active()
  local interface = remote.interfaces["nexus-threat"]
  if not (interface and interface.get_state) then
    return false
  end
  local ok, state = pcall(function()
    return remote.call("nexus-threat", "get_state")
  end)
  return ok and type(state) == "table" and state.storm_active == true
end

---@param summon table
---@param surface LuaSurface
---@return boolean ok
---@return string|nil message_key
function M.spawn(summon, surface)
  local position = spawn.find_position(summon, surface, cfg.GUARDIAN)
  local guardian = position and spawn.create_unit(surface, cfg.GUARDIAN, position)
  if not guardian then
    return false, "msg-fail-position"
  end
  records.add(summon, guardian, true, "boss")
  local units = { guardian }
  for _ = 1, ESCORTS do
    local spot = surface.find_non_colliding_position(WALKER, guardian.position, ESCORT_RADIUS, 1)
    local unit = spot and spawn.create_unit(surface, WALKER, spot)
    if unit then
      records.add(summon, unit, false, "escort")
      units[#units + 1] = unit
    end
  end
  for _ = 1, ESCORTS do
    -- flyers have no collision box
    local spot = util.offset(guardian.position, math.random() * 2 * math.pi, math.random() * ESCORT_RADIUS)
    local unit = spawn.create_unit(surface, FLYER, spot)
    if unit then
      records.add(summon, unit, false, "escort")
      units[#units + 1] = unit
    end
  end
  summon.guardian = { feeding = false }
  spawn.dispatch(surface, units, summon.position)
  return true, nil
end

---@param summon table
---@param surface LuaSurface
---@param force LuaForce
function M.tick(summon, surface, force)
  local seconds = summon.active_seconds
  if seconds % REDISPATCH_SECONDS == 0 then
    spawn.redispatch(summon, surface, records.commandable_units(summon))
  end
  local record = records.main(summon)
  if not record then
    return
  end
  local guardian = record.entity
  local state = summon.guardian
  local feeding = storm_active()
  if feeding ~= state.feeding then
    state.feeding = feeding
    util.say(force, { feeding and "nexus-bosses.msg-guardian-feeds" or "nexus-bosses.msg-guardian-starves" },
      feeding and util.COLORS.bad or util.COLORS.good)
  end
  if feeding then
    guardian.health = guardian.health + guardian.max_health * HEAL_SHARE
    rendering.draw_sprite({
      sprite = "nexus-bosses-spark",
      target = { entity = guardian, offset = { (math.random() - 0.5) * 3, -2 - math.random() * 2 } },
      surface = surface,
      tint = { r = 0.6, g = 0.85, b = 1 },
      x_scale = 2,
      y_scale = 2,
      orientation = math.random(),
      render_layer = "air-object",
      time_to_live = 60, -- one a second: a feeding guardian always sparks
    })
    if seconds % FEED_SOUND_SECONDS == 0 then
      util.play(force, "guardian-feeds")
    end
    if seconds % LIGHTNING_SECONDS == 0 then
      -- Nexus has no lightning generator (execute_lightning fails there): the entity, as Nexus-Threat makes it
      surface.create_entity({
        name = "lightning",
        position = util.offset(guardian.position, math.random() * 2 * math.pi, math.random() * LIGHTNING_RADIUS),
      })
    end
  end
end

---@param summon table
---@return LocalisedString|nil
function M.status(summon)
  return { summon.guardian.feeding and "nexus-bosses.status-guardian-feeds" or "nexus-bosses.status-guardian-starves" }
end

return M
