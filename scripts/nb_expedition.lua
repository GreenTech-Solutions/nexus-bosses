-- The expedition that came before the player. A wreck with a log lies on Nexus for every boss, on a ring around the
-- spawn of the player force, one ring a stage (cfg.EXPEDITION_RINGS); the wrecks of a stage appear when the stage
-- opens. Opening a wreck finds its log for the force: the dossier of the boss in the codex is the only place that tells
-- how to fight it. A victory marks the nearest wreck that is still unfound on the map. The detector (a shortcut) points
-- at the nearest unfound wreck and pings faster the closer it is.
--
--   storage.expedition.wrecks    [boss_id] = {entity, position}
--   storage.expedition.by_unit   [unit_number] = boss_id
--   storage.expedition.logs      [force_name] = {[boss_id] = tick}
--   storage.expedition.marked    [force_name] = {[boss_id] = true}
--   storage.expedition.detector  [player_index] = next tick of its ping

local cfg = require("lib.nb_data")
local util = require("scripts.nb_util")
local bearing = require("scripts.nb_bearing")

local M = {}

local SEARCH_RADIUS = 30
local DETECTOR_TICKS = 30
local ARROW_DISTANCE = 3

function M.init()
  storage.expedition = storage.expedition or {}
  local e = storage.expedition
  e.wrecks = e.wrecks or {}
  e.by_unit = e.by_unit or {}
  e.logs = e.logs or {}
  e.marked = e.marked or {}
  e.detector = e.detector or {}
end

---@param force_name string
---@return table<string, integer>
local function logs_of(force_name)
  ---@type table<string, integer>|nil
  local logs = storage.expedition.logs[force_name]
  if not logs then
    logs = {}
    storage.expedition.logs[force_name] = logs
  end
  return logs
end

---@param force_name string
---@param boss_id string
---@return boolean
function M.has_log(force_name, boss_id)
  ---@type table<string, integer>|nil
  local logs = storage.expedition.logs[force_name]
  return logs ~= nil and logs[boss_id] ~= nil
end

---@param force_name string
---@param stage integer
---@return boolean
local function stage_logs_complete(force_name, stage)
  for _, id in ipairs(cfg.CIRCLES[stage].bosses) do
    if not M.has_log(force_name, id) then
      return false
    end
  end
  return true
end

---@param force_name string
---@return boolean
local function all_logs(force_name)
  for stage = 1, #cfg.CIRCLES do
    if not stage_logs_complete(force_name, stage) then
      return false
    end
  end
  return true
end

---Places the wreck of a boss: a deterministic spot of its ring (the map seed and the boss), free ground near it.
---@param surface LuaSurface
---@param boss_id string
local function place_wreck(surface, boss_id)
  local boss = cfg.BOSSES[boss_id]
  local ring = cfg.EXPEDITION_RINGS[boss.circle] --[[@as integer[] ]]
  local seed = ((surface.map_gen_settings.seed or 0) + boss.circle * 7919 + boss.slot * 104729) % 4294967296
  local rng = game.create_random_generator(seed --[[@as uint32]])
  local name = cfg.WRECK_PREFIX .. rng(1, cfg.WRECK_VARIANTS)
  local center = game.forces.player.get_spawn_position(surface)
  for _ = 1, 8 do
    local wanted = util.offset(center, rng() * 2 * math.pi, rng(ring[1], ring[2]))
    util.ensure_generated(surface, wanted)
    local position = surface.find_non_colliding_position(name, wanted, SEARCH_RADIUS, 1)
    local wreck = position and surface.create_entity({ name = name, position = position, force = "neutral" })
    if wreck then
      wreck.destructible = false
      storage.expedition.wrecks[boss_id] = { entity = wreck, position = util.copy_position(wreck.position) }
      storage.expedition.by_unit[wreck.unit_number] = boss_id
      return
    end
  end
  log("[nexus-bosses] no ground for the expedition wreck of " .. boss_id)
end

---Places the wrecks of a stage that are not there yet.
---@param stage integer
function M.spawn_stage(stage)
  local surface = util.nexus()
  if not surface then
    return -- placed when Nexus is created
  end
  for _, id in ipairs(cfg.CIRCLES[stage].bosses) do
    local wreck = storage.expedition.wrecks[id]
    if not (wreck and wreck.entity.valid) then
      place_wreck(surface, id)
    end
  end
end

---The stages some player force has opened get their wrecks.
function M.spawn_open_stages()
  for stage, circle in ipairs(cfg.CIRCLES) do
    for _, force in pairs(game.forces) do
      local technology = force.technologies[circle.tech]
      if technology and technology.researched then
        M.spawn_stage(stage)
        break
      end
    end
  end
end

---@param technology LuaTechnology
function M.on_research_finished(technology)
  for stage, circle in ipairs(cfg.CIRCLES) do
    if technology.name == circle.tech then
      M.spawn_stage(stage)
    end
  end
end

---A player opened a wreck: its log is found for the force, and the codex shows it.
---@param player LuaPlayer
---@param entity LuaEntity
---@param codex table the codex module
function M.on_wreck_opened(player, entity, codex)
  local boss_id = storage.expedition.by_unit[entity.unit_number]
  if not boss_id then
    return
  end
  local force = player.force --[[@as LuaForce]]
  local logs = logs_of(force.name)
  local first = logs[boss_id] == nil
  if first then
    logs[boss_id] = game.tick
    util.say(force, { "nexus-bosses.msg-log-found", { "nexus-bosses.boss-" .. boss_id } }, util.COLORS.good)
    util.play(force, "trophy")
    local stage = cfg.BOSSES[boss_id].circle
    if stage_logs_complete(force.name, stage) then
      util.say(force, { "nexus-bosses.msg-stage-logs", { "nexus-bosses.stage-" .. cfg.CIRCLES[stage].stage } },
        util.COLORS.good)
    end
    if all_logs(force.name) then
      util.say(force, { "nexus-bosses.msg-all-logs" }, util.COLORS.good)
    end
    bearing.on_log_found(force)
  end
  player.opened = nil
  codex.open(player, boss_id)
end

---After a victory the nearest unfound wreck of the force is marked on the map.
---@param force LuaForce
---@param from MapPosition where the boss fell
function M.reveal_next(force, from)
  local surface = util.nexus()
  if not surface then
    return
  end
  local marked = storage.expedition.marked[force.name] or {}
  storage.expedition.marked[force.name] = marked
  local best, best_id, best_distance
  for id, wreck in pairs(storage.expedition.wrecks) do
    if wreck.entity.valid and not marked[id] and not M.has_log(force.name, id) then
      local distance = util.distance(from, wreck.position)
      if not best_distance or distance < best_distance then
        best, best_id, best_distance = wreck, id, distance
      end
    end
  end
  if not best then
    return
  end
  marked[best_id] = true
  force.chart(surface, { { best.position.x - 16, best.position.y - 16 }, { best.position.x + 16, best.position.y + 16 } })
  force.add_chart_tag(surface, { position = best.position, icon = { type = "entity", name = best.entity.name } })
  local x, y = util.xy(best.position)
  util.say(force, { "nexus-bosses.msg-wreck-revealed", math.floor(x), math.floor(y), surface.name }, util.COLORS.info)
end

-- Detector ----------------------------------------------------------------------------------------------------------

---@param player LuaPlayer
function M.toggle_detector(player)
  local on = not storage.expedition.detector[player.index]
  storage.expedition.detector[player.index] = on and game.tick or nil
  player.set_shortcut_toggled(cfg.SHORTCUT_DETECTOR, on)
  util.say(player, { on and "nexus-bosses.msg-detector-on" or "nexus-bosses.msg-detector-off" })
end

---@param distance number
---@return integer ticks between two pings
local function ping_interval(distance)
  if distance < 40 then
    return 30
  elseif distance < 120 then
    return 60
  elseif distance < 300 then
    return 120
  end
  return 240
end

---Every DETECTOR_TICKS for the players whose detector is on and who stand on Nexus.
---@param tick integer
function M.detector_tick(tick)
  local detector = storage.expedition.detector
  if next(detector) == nil then
    return
  end
  local surface = util.nexus()
  for index, next_ping in pairs(detector) do
    local player = game.get_player(index)
    local character = player and player.connected and player.character
    if not player then
      detector[index] = nil
    elseif character and surface and character.surface_index == surface.index then
      local here = character.position
      local hx, hy = util.xy(here)
      local force_name = player.force.name --[[@as string]]
      local best, best_distance
      for id, wreck in pairs(storage.expedition.wrecks) do
        if wreck.entity.valid and not M.has_log(force_name, id) then
          local distance = util.distance(here, wreck.position)
          if not best_distance or distance < best_distance then
            best, best_distance = wreck, distance
          end
        end
      end
      if best then
        local angle = math.atan2(best.position.y - hy, best.position.x - hx)
        rendering.draw_sprite({
          sprite = "utility/indication_arrow",
          orientation = (angle / (2 * math.pi) + 0.25) % 1,
          target = { entity = character, offset = { math.cos(angle) * ARROW_DISTANCE, math.sin(angle) * ARROW_DISTANCE } },
          surface = surface,
          players = { player },
          tint = { r = 0.6, g = 0.85, b = 1 },
          x_scale = 1.5,
          y_scale = 1.5,
          time_to_live = DETECTOR_TICKS + 1,
        })
        if tick >= next_ping then
          player.play_sound({ path = "nexus-bosses-detector" })
          detector[index] = tick + ping_interval(best_distance --[[@as number]])
        end
      end
    end
  end
end

---A force that found a log before 2.3 learns the bearings.
function M.sync_bearing()
  for force_name, logs in pairs(storage.expedition.logs) do
    local force = game.forces[force_name]
    if force and next(logs) then
      bearing.on_log_found(force)
    end
  end
end

---Plain data for the remote interface.
---@return table
function M.snapshot()
  local wrecks = {}
  for id, wreck in pairs(storage.expedition.wrecks) do
    wrecks[id] = { x = wreck.position.x, y = wreck.position.y, valid = wreck.entity.valid }
  end
  return { wrecks = wrecks, logs = storage.expedition.logs, marked = storage.expedition.marked }
end

---For tests: finds the log of a boss for a force, as opening its wreck would.
---@param force_name string
---@param boss_id string
function M.find_log(force_name, boss_id)
  logs_of(force_name)[boss_id] = game.tick
end

return M
