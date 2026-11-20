-- Guards of the finds. The first time a player comes within GUARD_RADIUS of an unfound wreck of the expedition or of a
-- found lair, precursors of its boss emerge around it and attack. Each place can trigger once on the map.
--
--   storage.guards.done     [key] = tick    key: "wreck:<boss_id>" | "lair:<boss_id>"
--   storage.guards.pending  {at, boss_id, position, force_name}[]: guards due after the warning circle

local cfg = require("lib.nb_data")
local util = require("scripts.nb_util")
local expedition = require("scripts.nb_expedition")
local bearing = require("scripts.nb_bearing")
local telegraph = require("scripts.nb_telegraph")

local M = {}

local GUARD_RADIUS = 40
local GUARD_DELAY = 3 * 60
local SPAWN_RADIUS_MIN = 6
local SPAWN_RADIUS_MAX = 12
local ATTACK_RADIUS = 20

function M.init()
  storage.guards = storage.guards or {}
  storage.guards.done = storage.guards.done or {}
  storage.guards.pending = storage.guards.pending or {}
end

---@param surface LuaSurface
---@param boss_id string
---@param center MapPosition
---@return LuaEntity|nil
local function lair_alert_target(surface, boss_id, center)
  local remains_name = cfg.LAIR_REMAINS_PREFIX .. boss_id
  for _, entity in ipairs(surface.find_entities_filtered({ name = remains_name, position = center, radius = 2 })) do
    if entity.valid then
      return entity
    end
  end
  return nil
end

---@param player LuaPlayer
---@param surface LuaSurface
---@param boss_id string
---@param center MapPosition
---@param key string
---@param alert_target LuaEntity
---@param icon_name string
local function wake(player, surface, boss_id, center, key, alert_target, icon_name)
  if storage.guards.done[key] then
    return
  end
  storage.guards.done[key] = game.tick
  local position = util.copy_position(center)
  telegraph.filling_circle(nil, surface, position, 12, GUARD_DELAY)
  player.add_custom_alert(alert_target, { type = "entity", name = icon_name },
    { "nexus-bosses.msg-guards-awake", { "nexus-bosses.boss-" .. boss_id } }, true)
  util.say(player, { "nexus-bosses.msg-guards-awake", { "nexus-bosses.boss-" .. boss_id } }, util.COLORS.bad)
  storage.guards.pending[#storage.guards.pending + 1] = {
    at = game.tick + GUARD_DELAY,
    boss_id = boss_id,
    position = position,
    force_name = player.force.name,
  }
end

---@param surface LuaSurface
---@param center MapPosition
---@param force_name string
---@return MapPosition
local function attack_position(surface, center, force_name)
  local target = util.copy_position(center)
  local nearest_distance
  local force = game.forces[force_name]
  if force then
    for _, player in ipairs(force.connected_players) do
      local character = player.character
      if character and character.valid and character.surface_index == surface.index then
        local distance = util.distance(center, character.position)
        if distance <= GUARD_RADIUS and (not nearest_distance or distance < nearest_distance) then
          target = util.copy_position(character.position)
          nearest_distance = distance
        end
      end
    end
  end
  return target
end

---@param surface LuaSurface
---@param pending {at: integer, boss_id: string, position: MapPosition, force_name: string}
local function emerge(surface, pending)
  local boss = cfg.BOSSES[pending.boss_id]
  if not boss then
    return
  end
  local center = pending.position
  local destination = attack_position(surface, center, pending.force_name)
  local amount = math.ceil(cfg.CIRCLES[boss.circle].precursors / 2)
  for _ = 1, amount do
    local name = boss.precursors[math.random(1, #boss.precursors)]
    local position
    for _ = 1, 12 do
      local wanted = util.offset(center, math.random() * 2 * math.pi,
        SPAWN_RADIUS_MIN + math.random() * (SPAWN_RADIUS_MAX - SPAWN_RADIUS_MIN))
      util.ensure_generated(surface, wanted)
      local candidate = surface.find_non_colliding_position(name, wanted, 2, 0.5)
      if candidate then
        local distance = util.distance(center, candidate)
        if distance >= SPAWN_RADIUS_MIN and distance <= SPAWN_RADIUS_MAX then
          position = candidate
          break
        end
      end
    end
    if position then
      local unit = surface.create_entity({ name = name, position = position, force = "enemy" })
      if unit then
        util.burrow(surface, position)
        local commandable = unit.commandable --[[@as LuaCommandable]]
        commandable.set_command({
          type = defines.command.attack_area,
          destination = destination,
          radius = ATTACK_RADIUS,
          distraction = defines.distraction.by_enemy,
        })
      end
    end
  end
end

---@param surface LuaSurface
---@param tick integer
local function process_pending(surface, tick)
  local remaining = {}
  for _, pending in ipairs(storage.guards.pending) do
    if tick >= pending.at then
      emerge(surface, pending)
    else
      remaining[#remaining + 1] = pending
    end
  end
  storage.guards.pending = remaining
end

---Every second.
function M.on_second()
  local surface = util.nexus()
  if not surface then
    return
  end
  process_pending(surface, game.tick)

  for _, player in ipairs(game.connected_players) do
    local character = player.character
    if character and character.valid and character.surface_index == surface.index then
      local force_name = player.force.name --[[@as string]]
      local here = character.position
      for boss_id, wreck in pairs(storage.expedition.wrecks) do
        local key = "wreck:" .. boss_id
        if not storage.guards.done[key] and wreck.entity.valid and not expedition.has_log(force_name, boss_id)
          and util.distance(here, wreck.position) <= GUARD_RADIUS then
          wake(player, surface, boss_id, wreck.position, key, wreck.entity, wreck.entity.name)
        end
      end
      for boss_id, position in pairs(storage.bearing.lairs) do
        local key = "lair:" .. boss_id
        if not storage.guards.done[key] and bearing.is_found(force_name, boss_id)
          and util.distance(here, position) <= GUARD_RADIUS then
          local pylon = storage.bearing.pylons[boss_id]
          local target = pylon and pylon.valid and pylon or lair_alert_target(surface, boss_id, position) or character
          wake(player, surface, boss_id, position, key, target, cfg.PYLON)
        end
      end
    end
  end
end

---Plain data for the remote interface.
---@return table
function M.snapshot()
  local done = {}
  for key, tick in pairs(storage.guards.done) do
    done[key] = tick
  end
  local pending = {}
  for _, entry in ipairs(storage.guards.pending) do
    pending[#pending + 1] = {
      at = entry.at,
      boss_id = entry.boss_id,
      position = util.copy_position(entry.position),
      force_name = entry.force_name,
    }
  end
  return { done = done, pending = pending }
end

---Clears guard state for an isolated in-game test.
function M.reset()
  storage.guards.done = {}
  storage.guards.pending = {}
end

return M
