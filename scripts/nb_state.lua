-- The storage of the mod. The modules keep no state of their own.
--   storage.progress        [force_name] = { defeated = { [boss_id] = true } }
--   storage.summon          the active summon or nil (scripts/nb_summon.lua)
--   storage.next_summon_id  counter
--   storage.ignore_presence test switch: the countdown runs without a player on Nexus
--   storage.storm_weakened  the Storm Guardian has fallen once
--   storage.bm_excluded     surfaces taken out of Big Monsters' list by the map setting (scripts/nb_bm.lua)

local cfg = require("lib.nb_data")
local summon = require("scripts.nb_summon")
local expedition = require("scripts.nb_expedition")

local M = {}

function M.init()
  storage.progress = storage.progress or {}
  storage.next_summon_id = storage.next_summon_id or 1
  storage.ignore_presence = storage.ignore_presence or false
  storage.storm_weakened = storage.storm_weakened or false
  storage.bm_excluded = storage.bm_excluded or {}
end

---Plain data for the remote interface: no LuaObjects.
---@return table
function M.snapshot()
  local state = {
    ignore_player_presence = storage.ignore_presence,
    storm_weakened = storage.storm_weakened,
    summon = summon.snapshot(),
    expedition = expedition.snapshot(),
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
