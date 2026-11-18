-- The storage of the mod. The modules keep no state of their own.
--   storage.progress        [force_name] = { defeated = { [boss_id] = true }, colossus_variants = { [variant_id] = true } }
--   storage.summon          the active summon or nil (scripts/nb_summon.lua)
--   storage.next_summon_id  counter
--   storage.colossus_next   [force_name] = variant_id, held until a Colossus victory
--   storage.next_colossus_variant test switch consumed by a Colossus selection
--   storage.next_angle      [force_name][boss_id] = side angle, held until the boss starts spawning
--   storage.ignore_presence test switch: the countdown runs without a player on Nexus
--   storage.countdown_override test switch: the next countdown in seconds; nil uses the setting
--   storage.storm_weakened  the Storm Guardian has fallen once
--   storage.expedition, storage.bearing, storage.guards, storage.storms, storage.story, storage.vault:
--                           scripts/nb_expedition.lua, nb_bearing.lua, nb_guards.lua, nb_storms.lua,
--                           nb_story.lua, nb_vault.lua

local cfg = require("lib.nb_data")
local summon = require("scripts.nb_summon")
local expedition = require("scripts.nb_expedition")
local bearing = require("scripts.nb_bearing")
local storms = require("scripts.nb_storms")
local story = require("scripts.nb_story")
local vault = require("scripts.nb_vault")
local guards = require("scripts.nb_guards")

local M = {}

function M.init()
  storage.progress = storage.progress or {}
  storage.next_summon_id = storage.next_summon_id or 1
  storage.ignore_presence = storage.ignore_presence or false
  storage.storm_weakened = storage.storm_weakened or false
end

---Plain data for the remote interface: no LuaObjects.
---@return table
function M.snapshot()
  local state = {
    ignore_player_presence = storage.ignore_presence,
    storm_weakened = storage.storm_weakened,
    summon = summon.snapshot(),
    expedition = expedition.snapshot(),
    bearing = bearing.snapshot(),
    guards = guards.snapshot(),
    storms = storms.snapshot(),
    story = story.snapshot(),
    vault = vault.snapshot(),
    defeated = {},
  }
  for force_name, record in pairs(storage.progress) do
    local defeated = {}
    for _, boss_id in ipairs(cfg.ORDER) do
      defeated[boss_id] = record.defeated[boss_id] == true
    end
    state.defeated[force_name] = defeated
  end
  return state
end

return M
