-- Storm Guardian: a walking electric giant with 20 walkers and 20 flyers. It feeds during Nexus-Threat storms, or
-- after 60 seconds without one it calls its own 40-second storm / 40-second calm cycle. During any storm it heals
-- 0.5 % of its health every second and calls lightning around itself. Charged shards reduce healing; a pylon weakens
-- lightning.

local cfg = require("lib.nb_data")
local util = require("scripts.nb_util")
local records = require("scripts.nb_records")
local spawn = require("scripts.nb_spawn")
local telegraph = require("scripts.nb_telegraph")

local M = {}

local WALKER = "walking-electric-unit-5"
local FLYER = "flying-electric-unit-5"
local ESCORTS = 20
local ESCORT_RADIUS = 20
local HEAL_SHARE = 0.005
local LIGHTNING_SECONDS = 3
local FEED_SOUND_SECONDS = 6
local LIGHTNING_RADIUS = 12
local LIGHTNING_TELEGRAPH_TICKS = 60
local OWN_STORM_WAIT = 60
local OWN_STORM_ON = 40
local OWN_STORM_OFF = 40

---@param summon NbSummon
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

---@param summon NbSummon
---@param surface LuaSurface
---@param force LuaForce
function M.tick(summon, surface, force)
  local seconds = summon.active_seconds
  if seconds % spawn.REDISPATCH_SECONDS == 0 then
    spawn.redispatch(summon, surface, records.commandable_units(summon))
  end
  local record = records.main(summon)
  if not record then
    return
  end
  local guardian = record.entity
  local state = assert(summon.guardian)
  local share = 1 - (summon.charge or 0) / cfg.CHARGES
  local threat_storm = util.storm_active()
  if threat_storm then
    state.last_storm = seconds
  end
  if not state.own_cycle and seconds - (state.last_storm or 0) >= OWN_STORM_WAIT then
    state.own_cycle = seconds
    util.say(force, { "nexus-bosses.msg-guardian-own-storm" }, util.COLORS.warning)
  end
  local own_elapsed = state.own_cycle and (seconds - state.own_cycle) % (OWN_STORM_ON + OWN_STORM_OFF) or nil
  local own_storm = own_elapsed ~= nil and own_elapsed < OWN_STORM_ON
  local storm = threat_storm or own_storm
  local feeding = share > 0 and storm
  if feeding ~= state.feeding then
    state.feeding = feeding
    util.say(force, { feeding and "nexus-bosses.msg-guardian-feeds" or "nexus-bosses.msg-guardian-starves" },
      feeding and util.COLORS.bad or util.COLORS.good)
  end
  if feeding then
    guardian.health = guardian.health + guardian.max_health * HEAL_SHARE * share
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
  end
  local lightning_interval = util.interval(summon, LIGHTNING_SECONDS)
  if storm and util.due(state, "next_lightning", seconds, lightning_interval) then
    if math.random() < 1 - (summon.weaken or 0) then
      local position = util.offset(guardian.position, math.random() * 2 * math.pi,
        math.random() * LIGHTNING_RADIUS)
      telegraph.filling_circle(summon, surface, position, 2, LIGHTNING_TELEGRAPH_TICKS)
      telegraph.queue(summon, "strike", LIGHTNING_TELEGRAPH_TICKS, { position = util.copy_position(position) })
    end
  end
end

---@param _summon NbSummon
---@param surface LuaSurface
---@param _force LuaForce
---@param entry NbPending
function M.on_pending(_summon, surface, _force, entry)
  if entry.kind == "strike" then
    util.strike(surface, entry.data.position)
  end
end

---@param summon NbSummon
---@return LocalisedString|nil
function M.status(summon)
  local state = summon.guardian
  local own_elapsed = state and state.own_cycle
    and (summon.active_seconds - state.own_cycle) % (OWN_STORM_ON + OWN_STORM_OFF) or nil
  if own_elapsed and own_elapsed < OWN_STORM_ON then
    return { "nexus-bosses.status-guardian-own-storm", math.max(0, math.ceil(OWN_STORM_ON - own_elapsed)) }
  end
  if state and state.feeding then
    return { "nexus-bosses.status-guardian-feeds" }
  elseif (summon.charge or 0) >= cfg.CHARGES then
    return { "nexus-bosses.status-guardian-charged" }
  end
  return { "nexus-bosses.status-guardian-starves" }
end

---@param summon NbSummon
---@return table
function M.snapshot(summon)
  local state = summon.guardian
  local own_elapsed = state and state.own_cycle
    and (summon.active_seconds - state.own_cycle) % (OWN_STORM_ON + OWN_STORM_OFF) or nil
  return {
    feeding = state ~= nil and state.feeding == true,
    own_storm = own_elapsed ~= nil and own_elapsed < OWN_STORM_ON,
  }
end

return M
