-- Migrations for saves from earlier versions of Nexus Bosses.

local cfg = require("lib.nb_data")
local summon = require("scripts.nb_summon")
local expedition = require("scripts.nb_expedition")
local bearing = require("scripts.nb_bearing")
local story = require("scripts.nb_story")
local vault = require("scripts.nb_vault")

local M = {}

---Runs each migration once when the mod configuration changes.
function M.run()
  storage.migrated = storage.migrated or {}
  local migrated = storage.migrated

  if not migrated["bm-summon"] then
    local active = storage.summon
    if active and active.bm then
      summon.cancel_refund("msg-summon-cancelled-update")
    end
    migrated["bm-summon"] = true
  end

  if not migrated["vault-relic"] then
    local surface = game.get_surface(cfg.VAULT_SURFACE)
    local vault_state = storage.vault
    if surface and vault_state and not (vault_state.relic and vault_state.relic.valid) then
      local relics = surface.find_entities_filtered({ name = cfg.RELIC, limit = 1 })
      if relics[1] then
        vault_state.relic = relics[1]
      end
    end
    migrated["vault-relic"] = true
  end

  if not migrated.glyphs then
    for _, force in pairs(game.forces) do
      if force.name ~= "enemy" and force.name ~= "neutral" then
        if story.is_found(force.name, "camp") then
          vault.earn(force, "camp")
        end

        local all_logs = true
        local has_lair_win = false
        for _, boss_id in ipairs(cfg.ORDER) do
          if not expedition.has_log(force.name, boss_id) then
            all_logs = false
          end
          if bearing.wins_of(force.name, boss_id) > 0 then
            has_lair_win = true
          end
        end
        if all_logs then
          vault.earn(force, "logs")
        end
        if has_lair_win then
          vault.earn(force, "lair")
        end
      end
    end
    migrated.glyphs = true
  end

  if not migrated["whisper-timers"] then
    storage.whisper.next = {}
    migrated["whisper-timers"] = true
  end
end

return M
