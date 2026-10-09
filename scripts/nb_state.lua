-- The storage of the mod. Everything the scripts remember is here; the modules keep no state of their own.
--
--   storage.progress        [force_name] = { defeated = { [boss_id] = true } }
--   storage.summon          the active summon or nil (built in scripts/nb_summon.lua):
--                           { id, boss, circle, force, surface_index, phase = "countdown" | "spawning" | "active",
--                             beacon, beacon_unit, item, quality, position, countdown, countdown_total, paused,
--                             tracked = { record... }, by_unit = { [unit_number] = record }, bm = {...}|nil,
--                             lair = {...}|nil, territory, label, tag, death_filters, active_seconds, ... }
--   storage.next_summon_id  counter
--   storage.ignore_presence debug switch: the countdown runs without a player on Nexus
--   storage.storm_weakened  the Storm Guardian has fallen once (the multiplier 0.5 is applied and re-applied)

local cfg = require("lib.nb_data")
local records = require("scripts.nb_records")

local M = {}

---Creates the missing keys; safe to call again.
function M.init()
  storage.progress = storage.progress or {}
  storage.next_summon_id = storage.next_summon_id or 1
  if storage.ignore_presence == nil then
    storage.ignore_presence = false
  end
  if storage.storm_weakened == nil then
    storage.storm_weakened = false
  end
end

---Plain data for the remote interface: no LuaObjects, so a test can serialise it.
---@return table
function M.snapshot()
  local summon = storage.summon
  local state = {
    ignore_player_presence = storage.ignore_presence == true,
    storm_weakened = storage.storm_weakened == true,
    active = summon ~= nil,
    defeated = {},
    circles = {},
  }
  for force_name, force in pairs(game.forces) do
    if force_name ~= "enemy" and force_name ~= "neutral" then
      local record = storage.progress[force_name]
      local defeated = {}
      if record then
        for boss_id in pairs(record.defeated) do
          defeated[boss_id] = true
        end
      end
      state.defeated[force_name] = defeated

      local circles = {}
      for index, circle in ipairs(cfg.CIRCLES) do
        local done = true
        for _, boss_id in ipairs(circle.bosses) do
          done = done and defeated[boss_id] == true
        end
        local unlock = force.technologies[circle.tech]
        local reward = force.technologies[circle.reward]
        circles[index] = {
          done = done,
          unlocked = unlock ~= nil and unlock.researched,
          reward = circle.reward,
          reward_researched = reward ~= nil and reward.researched,
        }
      end
      state.circles[force_name] = circles
    end
  end

  if summon then
    local beacon = summon.beacon
    local beacon_valid = beacon ~= nil and beacon.valid
    state.summon = {
      id = summon.id,
      boss = summon.boss,
      circle = summon.circle,
      force = summon.force,
      surface_index = summon.surface_index,
      phase = summon.phase,
      paused = summon.paused,
      beacon_valid = beacon_valid,
      beacon_position = { x = summon.position.x, y = summon.position.y },
      countdown_left = summon.countdown,
      countdown_total = summon.countdown_total,
      active_seconds = summon.active_seconds,
      tracked = records.snapshot(summon),
      appear_position = summon.appear_position and { x = summon.appear_position.x, y = summon.appear_position.y } or nil,
      territory = summon.territory ~= nil and summon.territory.valid,
      spawn_note = summon.spawn_note, -- nil, or why the boss is not 150-250 tiles from the beacon on free ground
      spawn_distance = summon.spawn_distance,
    }
    if summon.lair then
      local turrets = 0
      for _, turret in ipairs(summon.lair.turrets) do
        if turret.valid then
          turrets = turrets + 1
        end
      end
      state.summon.lair_turrets = turrets
      state.summon.lair_ammo_missing = summon.lair.ammo_missing == true
    end
    if summon.bm then
      state.summon.bm = {
        event = summon.bm.event,
        attempts = summon.bm.attempts,
        window_left = summon.bm.window,
        prototype_names = #summon.bm.names,
        explore_chunks = summon.bm.explore,
        last_error = summon.bm.error,
      }
    end
  end
  return state
end

return M
