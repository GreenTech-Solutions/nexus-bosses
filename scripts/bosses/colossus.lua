-- The Colossus is one of six Big Monsters units copied under Nexus Bosses' names. Each variant has its own attack.

local cfg = require("lib.nb_data")
local util = require("scripts.nb_util")
local records = require("scripts.nb_records")
local spawn = require("scripts.nb_spawn")
local telegraph = require("scripts.nb_telegraph")
local resistance = require("scripts.nb_resist")
local progress = require("scripts.nb_progress")

local M = {}

local INTERVALS = {
  fire = 4,
  storm = 3,
  armored = 40,
  mother = 20,
  ["fire-spitter"] = 15,
  ["acid-spitter"] = 15,
}
local TELEGRAPH_SECONDS = {
  fire = 1,
  storm = 1,
  armored = 3,
  mother = 3,
  ["fire-spitter"] = 2,
  ["acid-spitter"] = 2,
}
local SHIELD_SECONDS = 10
local SPITTER_RADIUS = 40
local SPITTER_ATTACK_RADIUS = 6
local SPITTER_SHOTS = 5
local MOTHER_ESCORTS = 6
local SPITTER_PROJECTILES = {
  ["fire-spitter"] = cfg.COLOSSUS_FIRE_PROJECTILE,
  ["acid-spitter"] = cfg.COLOSSUS_ACID_PROJECTILE,
}

function M.init()
  storage.colossus_next = storage.colossus_next or {}
  local summon = storage.summon
  if summon and summon.boss == "colossus" and summon.variant and not storage.colossus_next[summon.force] then
    storage.colossus_next[summon.force] = summon.variant
  end
end

---@param force_name string
---@return string variant_id
function M.ensure_next(force_name)
  storage.colossus_next = storage.colossus_next or {}
  if storage.next_colossus_variant then
    storage.colossus_next[force_name] = storage.next_colossus_variant
    storage.next_colossus_variant = nil
  end
  ---@type string|nil
  local variant = storage.colossus_next[force_name]
  if not variant then
    variant = (cfg.COLOSSUS_VARIANTS[math.random(#cfg.COLOSSUS_VARIANTS)] --[[@as table]]).id
    storage.colossus_next[force_name] = variant
  end
  return variant --[[@as string]]
end

---@param surface LuaSurface
---@param summon NbSummon
---@param position MapPosition
---@return LuaEntity|nil
local function best_spitter_target(surface, summon, position)
  local turrets = spawn.targets(surface, summon, position, SPITTER_RADIUS, { types = cfg.TURRET_TYPES })
  table.sort(turrets, function(a, b)
    local distance_a = util.distance(position, a.position)
    local distance_b = util.distance(position, b.position)
    if distance_a == distance_b then
      return (a.unit_number or 0) < (b.unit_number or 0)
    end
    return distance_a < distance_b
  end)

  local best, best_count, best_distance
  for _, turret in ipairs(turrets) do
    local count = surface.count_entities_filtered({
      position = turret.position,
      radius = SPITTER_ATTACK_RADIUS,
      force = summon.force,
      type = cfg.TURRET_TYPES,
    })
    local distance = util.distance(position, turret.position)
    if not best_count or count > best_count or (count == best_count and distance < best_distance) then
      best, best_count, best_distance = turret, count, distance
    end
  end
  return best
end

---@param summon NbSummon
function M.prepare(summon)
  summon.variant = M.ensure_next(summon.force)
  summon.variant_entity = cfg.COLOSSUS_PREFIX .. summon.variant
  summon.watch[#summon.watch + 1] = summon.variant_entity
end

---@param summon NbSummon
---@return LocalisedString
function M.countdown_note(summon)
  local entity_name = assert(summon.variant_entity)
  return { "nexus-bosses.msg-colossus-variant", { "entity-name." .. entity_name } }
end

---@param summon NbSummon
---@return table
function M.snapshot(summon)
  local shield = summon.colossus and summon.colossus.shield
  return {
    variant = summon.variant,
    variant_entity = summon.variant_entity,
    shield = shield and { until_tick = shield.until_tick, absorbed = shield.absorbed, limit = shield.limit },
  }
end

---@param summon NbSummon
local function clear_shield(summon)
  local state = summon.colossus
  if not state then
    return
  end
  local render = state.shield_render
  if render and render.valid then
    render.destroy()
  end
  state.shield_render = nil
  state.shield = nil
end

---@param summon NbSummon
---@param surface LuaSurface
---@return boolean ok
---@return string|nil message_key
function M.spawn(summon, surface)
  local entity_name = assert(summon.variant_entity)
  local position = spawn.find_position(summon, surface, entity_name)
  local boss = position and surface.create_entity({
    name = entity_name,
    position = position,
    force = "enemy",
  })
  if not boss then
    return false, "msg-fail-position"
  end
  records.add(summon, boss, true, "boss")
  summon.colossus = {}
  spawn.dispatch(surface, { boss }, summon.position)
  return true, nil
end

---@param summon NbSummon
---@param surface LuaSurface
---@param boss LuaEntity
local function schedule_attack(summon, surface, boss)
  local variant = summon.variant
  local warning = TELEGRAPH_SECONDS[variant] * 60
  local data = {}
  local kind = "colossus-" .. variant

  if variant == "fire" then
    local point = util.offset(boss.position, math.random() * 2 * math.pi, math.random() * 5)
    telegraph.filling_circle(summon, surface, point, 3, warning)
    data.position = util.copy_position(point)
  elseif variant == "storm" then
    telegraph.ring(summon, surface, boss, 6, warning)
  elseif variant == "armored" then
    telegraph.ring(summon, surface, boss, 8, warning)
  elseif variant == "mother" then
    local count = math.min(MOTHER_ESCORTS, math.max(0, cfg.ESCORT_CAP - #records.of_role(summon, "escort")))
    if count == 0 then
      return
    end
    local boss_x, boss_y = util.xy(boss.position)
    local beacon_x, beacon_y = util.xy(summon.position)
    local angle = math.atan2(beacon_y - boss_y, beacon_x - boss_x)
    local point = util.offset(boss.position, angle, 10)
    telegraph.filling_circle(summon, surface, point, 4, warning)
    data.position = util.copy_position(point)
    data.count = count
  elseif variant == "fire-spitter" or variant == "acid-spitter" then
    local turret = best_spitter_target(surface, summon, boss.position)
    if not turret then
      return
    end
    data.position = util.copy_position(turret.position)
    telegraph.filling_circle(summon, surface, data.position, SPITTER_ATTACK_RADIUS, warning)
  end

  telegraph.queue(summon, kind, warning, data)
end

---@param summon NbSummon
---@param surface LuaSurface
---@param position MapPosition
---@param count integer
local function spawn_mother_escort(summon, surface, position, count)
  local units = {}
  count = math.min(count, math.max(0, cfg.ESCORT_CAP - #records.of_role(summon, "escort")))
  for _ = 1, count do
    local spot = surface.find_non_colliding_position("behemoth-biter", position, 8, 1)
    local unit = spot and spawn.create_unit(surface, "behemoth-biter", spot)
    if unit then
      records.add(summon, unit, false, "escort")
      units[#units + 1] = unit
    end
  end
  spawn.dispatch(surface, units, summon.position)
end

---@param summon NbSummon
---@param surface LuaSurface
---@param entry NbPending
function M.on_pending(summon, surface, _force, entry)
  local boss = records.main(summon)
  if not boss then
    return
  end
  local state = assert(summon.colossus)

  if entry.kind == "colossus-fire" then
    local point = entry.data.position
    surface.create_entity({
      name = cfg.COLOSSUS_FIRE_PROJECTILE,
      position = point,
      target_position = point,
      source = boss.entity,
      force = "enemy",
      speed = 1,
    })
  elseif entry.kind == "colossus-storm" then
    surface.create_entity({ name = cfg.COLOSSUS_STORM_EXPLOSION, position = boss.entity.position, force = "enemy" })
  elseif entry.kind == "colossus-armored" then
    state.shield = {
      until_tick = game.tick + SHIELD_SECONDS * 60,
      absorbed = 0,
      limit = 0.05 * boss.entity.max_health,
    }
    state.shield_render = telegraph.ring(summon, surface, boss.entity, 8, SHIELD_SECONDS * 60)
  elseif entry.kind == "colossus-mother" then
    spawn_mother_escort(summon, surface, entry.data.position, entry.data.count or MOTHER_ESCORTS)
  elseif entry.kind == "colossus-fire-spitter" or entry.kind == "colossus-acid-spitter" then
    local projectile = SPITTER_PROJECTILES[summon.variant]
    local center = entry.data.position
    for _ = 1, SPITTER_SHOTS do
      local target = util.offset(center, math.random() * 2 * math.pi, math.random() * SPITTER_ATTACK_RADIUS)
      surface.create_entity({
        name = projectile,
        position = boss.entity.position,
        target_position = target,
        source = boss.entity,
        force = "enemy",
        speed = 1,
      })
    end
  end
end

---@param summon NbSummon
---@param event EventData.on_entity_damaged
function M.on_damaged(summon, event)
  local state = summon.colossus
  local shield = state and state.shield
  local entity = event.entity
  local record = entity.unit_number and summon.by_unit[entity.unit_number]
  if not (shield and record and record.entity == entity and record.name == summon.variant_entity) then
    return
  end
  if game.tick >= shield.until_tick then
    clear_shield(summon)
    return
  end

  local amount = event.final_damage_amount
  if amount <= 0 then
    return
  end
  if entity.valid and entity.health then
    entity.health = entity.health + amount
  end

  local weak = resistance.of(record.name --[[@as string]])
  for _, damage_type in ipairs(weak) do
    if event.damage_type.name == damage_type then
      shield.absorbed = shield.absorbed + amount
      if shield.absorbed >= shield.limit then
        clear_shield(summon)
        local force = game.forces[summon.force]
        if force then
          util.say(force, { "nexus-bosses.msg-colossus-shield-broken" }, util.COLORS.good)
        end
      end
      break
    end
  end
end

---@param summon NbSummon
---@param surface LuaSurface
---@param _force LuaForce
function M.tick(summon, surface, _force)
  local record = records.main(summon)
  if not record then
    return
  end
  local boss = record.entity
  local seconds = summon.active_seconds
  local state = assert(summon.colossus)

  if seconds % spawn.REDISPATCH_SECONDS == 0 then
    spawn.redispatch(summon, surface, records.commandable_units(summon))
  end

  local shield = state.shield
  if shield and game.tick >= shield.until_tick then
    clear_shield(summon)
  end

  local interval = util.interval(summon, INTERVALS[summon.variant], true)
  if util.due(state, "next_attack", seconds, interval) then
    schedule_attack(summon, surface, boss)
  end
end

---@param summon NbSummon
---@return LocalisedString|nil
function M.status(summon)
  local state = summon.colossus
  if not state then
    return nil
  end
  local interval = util.interval(summon, INTERVALS[summon.variant], true)
  if not interval then
    return { "nexus-bosses.status-suppressed" }
  end
  local shield = state.shield
  if shield and game.tick < shield.until_tick then
    local main = records.main(summon)
    local max_health = main and main.entity.max_health or shield.limit / 0.05
    local more = max_health > 0 and math.ceil(math.max(0, shield.limit - shield.absorbed) / max_health * 100) or 0
    return {
      "nexus-bosses.status-colossus-shield",
      math.ceil((shield.until_tick - game.tick) / 60),
      more,
    }
  end

  for _, entry in ipairs(summon.pending or {}) do
    if entry.kind:find("^colossus%-") then
      local remaining = math.max(0, math.ceil((entry.at - game.tick) / 60))
      return {
        "nexus-bosses.status-colossus-attack",
        { "nexus-bosses.colossus-attack-" .. summon.variant },
        remaining,
      }
    end
  end

  local next_attack = state.next_attack
  if not next_attack then
    return { "nexus-bosses.status-colossus-attack", { "nexus-bosses.colossus-attack-" .. summon.variant },
      math.ceil(interval) }
  end
  local remaining = math.max(0, math.ceil(next_attack - summon.active_seconds))
  return {
    "nexus-bosses.status-colossus-attack",
    { "nexus-bosses.colossus-attack-" .. summon.variant },
    remaining,
  }
end

---@param summon NbSummon
function M.on_victory(summon)
  local force = game.forces[summon.force]
  local variant = summon.variant
  if not variant then
    return
  end
  progress.mark_colossus_variant(force, variant)
  storage.colossus_next = storage.colossus_next or {}
  storage.colossus_next[force.name] = nil
  M.ensure_next(force.name)
end

---@param source_name string
---@param destination LuaForce
function M.on_forces_merged(source_name, destination)
  storage.colossus_next = storage.colossus_next or {}
  local variant = storage.colossus_next[source_name]
  if variant and not storage.colossus_next[destination.name] then
    storage.colossus_next[destination.name] = variant
  end
  storage.colossus_next[source_name] = nil
end

return M
