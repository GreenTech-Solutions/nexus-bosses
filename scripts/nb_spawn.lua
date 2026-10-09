-- The bosses that the mod spawns itself: Arachnid Queen, Toxic Lair, Storm Guardian, Host Worm.
-- (The other five come from Big-Monsters, see nb_bm.lua.)
--
-- Placement. The boss appears 150-250 tiles from the beacon, on a free spot with no player buildings around it (when
-- every spot of the ring is near buildings, the least crowded one), and goes to the beacon: units get an attack_area
-- command to the position of the beacon and, every 45 seconds, a fresh one to the nearest building of the player. The
-- units are told not to destroy themselves when a command fails, and not to return to a spawner.
--
-- The Toxic Lair is a spawner and cannot walk. Every two minutes the units it owns (at most seven) march on the
-- nearest building of the player, each with a command of its own (a unit that joins a unit group is released from the
-- spawner, which would then build seven more); the spawner replaces the dead ones. Ten infected turrets of
-- Toxic_biters stand around it (4 laser, 4 gun, 2 artillery) and are supplied the way Toxic_biters supplies its own:
-- the gun turrets get magazines of a kind their gun takes (the ammo categories of this pack are not the vanilla ones)
-- and are refilled when they run dry, the artillery turrets get 40 shells once, and the laser turrets need no ammo;
-- their energy buffer is topped up every five seconds because the drain of an unpowered turret would empty it.
--
-- The Host Worm is a segmented unit (Space Age demolisher). It is created with a territory around the beacon
-- (five by five chunks) and the AI state "investigating" towards the beacon; every 15 seconds it is put into
-- "enraged_at_target" against the nearest building of the player, which is the strongest order the API has for it.
-- When its trial ends without a victory the worm is released (see M.release).

local cfg = require("lib.nb_data")
local util = require("scripts.nb_util")
local records = require("scripts.nb_records")

local M = {}

local SPAWN_MIN = 150
local SPAWN_MAX = 250
local ESCORT_RADIUS = 14
local GUARD_RADIUS = 20
local ATTACK_RADIUS = 45
local BUILDING_SEARCH_RADIUS = 600
local REDISPATCH_SECONDS = 45
local LAIR_UPKEEP_SECONDS = 5
local LAIR_SORTIE_SECONDS = 120
local WORM_ORDER_SECONDS = 15
local TERRITORY_CHUNK_RADIUS = 2

local QUEEN = "maf-boss-arachnid-biter-10"
local QUEEN_COPY = "nexus-arachnid-queen" -- made when the health of the bosses is scaled (prototypes/nb_enemies.lua)
local LEVIATHAN = "arachnid-biter-leviathan-unit"
local GUARDIAN = "walking-electric-unit-boss-10"
local GUARDIAN_COPY = "nexus-storm-guardian"
local WALKER = "walking-electric-unit-5"
local FLYER = "flying-electric-unit-5"
local LAIR = "nexus-toxic-lair"
local WORM = "nexus-host-worm"

-- turrets around the lair: {prototype, dx, dy} from the position of the lair
local LAIR_TURRETS = {
  { "tb_infected_laser_turret", -11, -7 },
  { "tb_infected_laser_turret", 11, -7 },
  { "tb_infected_laser_turret", -11, 8 },
  { "tb_infected_laser_turret", 11, 8 },
  { "tb_infected_gun_turret", -13, 0.5 },
  { "tb_infected_gun_turret", 13, 0.5 },
  { "tb_infected_gun_turret", -1, -8.5 },
  { "tb_infected_gun_turret", -1, 9.5 },
  { "tb_infected_artillery_turret", -16, -11 },
  { "tb_infected_artillery_turret", 16, 11 },
}

-- Magazines for the gun turrets, the best first: the vanilla names of 2.1 (which renamed the firearm magazine) and
-- the ones of Krastorio 2. Only a magazine of a category that the gun of the turret takes is used: in a Krastorio 2 pack
-- firearm-magazine and piercing-rounds-magazine are of the category "kr-pistol", while the gun turret of Toxic_biters
-- takes "bullet".
local AMMO = {
  "armor-piercing-rifle-magazine",
  "kr-armor-piercing-rifle-magazine",
  "piercing-rounds-magazine",
  "rifle-magazine",
  "kr-rifle-magazine",
  "firearm-magazine",
}

---A unit of the enemy force that keeps living when its commands fail.
---@param surface LuaSurface
---@param name string
---@param position MapPosition
---@return LuaEntity|nil
local function create_unit(surface, name, position)
  local unit = surface.create_entity({ name = name, position = position, force = "enemy" })
  if unit and unit.valid then
    local ai = unit.ai_settings
    if ai then
      ai.allow_destroy_when_commands_fail = false
      ai.allow_try_return_to_spawner = false
    end
    return unit
  end
  return nil
end

---The nearest player-built military target near the beacon, for the orders of the bosses.
---@param surface LuaSurface
---@param position MapPosition the position of the boss or its group
---@param beacon_position MapPosition
---@param force_name string the force that placed the beacon
---@return LuaEntity|nil
local function nearest_building(surface, position, beacon_position, force_name)
  -- The engine's nearest-enemy query also sees map-generated Fulgoran ruin attractors on Nexus: they use the player
  -- force and can be military targets, but are not part of the player's base. Keep the search around the beacon and
  -- require a player as last_user so autoplace entities cannot pull a boss away from it.
  -- Only military targets come back: without the filter a large base returned tens of thousands of belts and poles
  -- to the Lua loop below, every 15 to 45 seconds of a fight.
  local targets = surface.find_entities_filtered({
    position = beacon_position,
    radius = BUILDING_SEARCH_RADIUS,
    force = force_name,
    is_military_target = true,
  })
  local nearest, nearest_distance
  for _, target in ipairs(targets) do
    if target.valid and target.type ~= "lightning-attractor" and
        target.name:sub(1, #cfg.BEACON_PREFIX) ~= cfg.BEACON_PREFIX and target.last_user and target.is_military_target then
      local distance = util.distance(position, target.position)
      if distance <= BUILDING_SEARCH_RADIUS and (not nearest_distance or distance < nearest_distance) then
        nearest = target
        nearest_distance = distance
      end
    end
  end
  return nearest
end

---@param target MapPosition
---@return Command
local function attack_command(target)
  return {
    type = defines.command.compound,
    structure_type = defines.compound_command.return_last,
    commands = {
      {
        type = defines.command.attack_area,
        destination = target,
        radius = ATTACK_RADIUS,
        distraction = defines.distraction.by_anything,
      },
      { type = defines.command.wander, radius = ATTACK_RADIUS, distraction = defines.distraction.by_enemy },
    },
  }
end

---Sends the units to attack the area around the target: the walkers as one group, the flyers as another (a group
---moves at the pace and along the path of its slowest members).
---@param surface LuaSurface
---@param units LuaEntity[]
---@param target MapPosition
function M.dispatch(surface, units, target)
  ---@type LuaEntity[][]
  local batches = { {}, {} }
  for _, unit in ipairs(units) do
    if unit.valid and unit.commandable then
      local batch = batches[unit.name == FLYER and 2 or 1]
      batch[#batch + 1] = unit
    end
  end
  for _, members in ipairs(batches) do
    if #members > 0 then
      local group = surface.create_unit_group({ position = members[1].position, force = members[1].force })
      for _, unit in ipairs(members) do
        group.add_member(unit)
      end
      group.set_command(attack_command(target))
      group.start_moving()
    end
  end
end

---Puts ammo that the gun of the turret takes into it: the magazines of the list above first, then any ammo item of a
---category the gun accepts. The result of the insertion decides; nothing else is tried after the first success.
---@param turret LuaEntity
---@param count integer
---@return boolean true when something was inserted
local function insert_ammo(turret, count)
  local parameters = turret.prototype.attack_parameters
  local accepted = {}
  for _, category in ipairs(parameters and parameters.ammo_categories or {}) do
    accepted[category] = true
  end
  local any = next(accepted) ~= nil
  local tried = {}
  local function try(name)
    if tried[name] then
      return false
    end
    tried[name] = true
    local item = prototypes.item[name]
    if not (item and item.type == "ammo") then
      return false
    end
    local category = item.ammo_category
    if any and not (category and accepted[category.name]) then
      return false
    end
    return turret.insert({ name = name, count = count }) > 0
  end
  for _, name in ipairs(AMMO) do
    if try(name) then
      return true
    end
  end
  local names = {}
  for name, item in pairs(prototypes.get_item_filtered({ { filter = "type", type = "ammo" } })) do
    local category = item.ammo_category
    if category and accepted[category.name] then
      names[#names + 1] = name
    end
  end
  table.sort(names)
  for _, name in ipairs(names) do
    if try(name) then
      return true
    end
  end
  return false
end

---Puts a turret into working order (see the header). The artillery is supplied once, when `initial` is true.
---@param summon table
---@param turret LuaEntity
---@param initial boolean|nil the turret has just been placed
local function arm_turret(summon, turret, initial)
  local kind = turret.type
  if kind == "ammo-turret" then
    if turret.get_item_count() == 0 and not insert_ammo(turret, 10) and not summon.lair.ammo_missing then
      summon.lair.ammo_missing = true
      log("[nexus-bosses] no ammo fits the gun turret " .. turret.name .. ": the guards of the lair have no bullets")
    end
  elseif kind == "artillery-turret" then
    if initial then
      if prototypes.item["artillery-shell"] then
        turret.insert({ name = "artillery-shell", count = 40 })
      end
      turret.artillery_auto_targeting = true
    end
  elseif kind == "electric-turret" then
    local size = turret.electric_buffer_size
    if size then
      turret.energy = size
    end
  end
end

---@param summon table
---@param surface LuaSurface
---@param center MapPosition
local function place_lair_turrets(summon, surface, center)
  local cx, cy = util.xy(center)
  local missing = {}
  for _, spec in ipairs(LAIR_TURRETS) do
    local name = spec[1]
    if prototypes.entity[name] then
      local wanted = { x = cx + spec[2], y = cy + spec[3] }
      local position = surface.find_non_colliding_position(name, wanted, 6, 0.5)
      if position then
        local turret = surface.create_entity({ name = name, position = position, force = "enemy" })
        if turret and turret.valid then
          arm_turret(summon, turret, true)
          summon.lair.turrets[#summon.lair.turrets + 1] = turret
        end
      end
    else
      missing[name] = true
    end
  end
  if next(missing) then
    local names = {}
    for name in pairs(missing) do
      names[#names + 1] = name
    end
    table.sort(names)
    log("[nexus-bosses] Toxic_biters makes no " .. table.concat(names, ", ") ..
      " (is its startup setting tb-allow-infection off?): the lair has no such guards")
  end
  summon.lair.turrets_placed = #summon.lair.turrets
end

---@param names string[]
---@return boolean true when every prototype exists
local function all_exist(names)
  for _, name in ipairs(names) do
    if not prototypes.entity[name] then
      return false
    end
  end
  return true
end

---A position for the boss 150-250 tiles from the beacon (see util.find_spawn_position). What was not perfect about
---it is logged and kept in the summon (spawn_note, spawn_distance) for the state of the remote interface.
---@param summon table
---@param surface LuaSurface
---@param name string entity prototype
---@return MapPosition|nil
local function find_position(summon, surface, name)
  local position, note = util.find_spawn_position(surface, summon.position, name, SPAWN_MIN, SPAWN_MAX, summon.force)
  summon.spawn_note = note
  if position then
    summon.spawn_distance = util.distance(position, summon.position)
    if note then
      log(string.format("[nexus-bosses] %s: the position of %s is %s, %d tiles from the beacon", summon.boss, name,
        note, math.floor(summon.spawn_distance)))
    end
  end
  return position
end

---@param summon table
---@param surface LuaSurface
---@return boolean ok
---@return string|nil message_key
local function spawn_queen(summon, surface)
  local queen_name = prototypes.entity[QUEEN_COPY] and QUEEN_COPY or QUEEN
  if not all_exist({ queen_name, LEVIATHAN }) then
    return false, "msg-fail-prototype"
  end
  local position = find_position(summon, surface, queen_name)
  local queen = position and create_unit(surface, queen_name, position)
  if not (position and queen) then
    return false, "msg-fail-position"
  end
  records.add(summon, queen, queen_name, true, "boss")
  local units = { queen }
  for _ = 1, 4 do
    local spot = surface.find_non_colliding_position(LEVIATHAN, position, ESCORT_RADIUS, 1)
    local unit = spot and create_unit(surface, LEVIATHAN, spot)
    if unit then
      records.add(summon, unit, LEVIATHAN, false, "escort")
      units[#units + 1] = unit
    end
  end
  summon.appear_position = util.copy_position(position)
  M.dispatch(surface, units, summon.position)
  return true, nil
end

---@param summon table
---@param surface LuaSurface
---@return boolean ok
---@return string|nil message_key
local function spawn_guardian(summon, surface)
  local boss_name = prototypes.entity[GUARDIAN_COPY] and GUARDIAN_COPY or GUARDIAN
  if not all_exist({ boss_name, WALKER, FLYER }) then
    return false, "msg-fail-prototype"
  end
  local position = find_position(summon, surface, boss_name)
  local guardian = position and create_unit(surface, boss_name, position)
  if not (position and guardian) then
    return false, "msg-fail-position"
  end
  records.add(summon, guardian, boss_name, true, "boss")
  local units = { guardian }
  for _ = 1, 20 do
    local spot = surface.find_non_colliding_position(WALKER, position, GUARD_RADIUS, 1)
    local unit = spot and create_unit(surface, WALKER, spot)
    if unit then
      records.add(summon, unit, WALKER, false, "escort")
      units[#units + 1] = unit
    end
  end
  local px, py = util.xy(position)
  for _ = 1, 20 do
    -- flying units have no collision box: any point will do
    local spot = {
      x = px + (math.random() * 2 - 1) * GUARD_RADIUS,
      y = py + (math.random() * 2 - 1) * GUARD_RADIUS,
    }
    local unit = create_unit(surface, FLYER, spot)
    if unit then
      records.add(summon, unit, FLYER, false, "escort")
      units[#units + 1] = unit
    end
  end
  summon.appear_position = util.copy_position(position)
  M.dispatch(surface, units, summon.position)
  return true, nil
end

---@param summon table
---@param surface LuaSurface
---@return boolean ok
---@return string|nil message_key
local function spawn_lair(summon, surface)
  if not prototypes.entity[LAIR] then
    return false, "msg-fail-prototype"
  end
  local position = find_position(summon, surface, LAIR)
  local spawner = position and surface.create_entity({ name = LAIR, position = position, force = "enemy" })
  if not (position and spawner and spawner.valid) then
    return false, "msg-fail-position"
  end
  records.add(summon, spawner, LAIR, true, "boss")
  summon.lair = { spawner = spawner, turrets = {} }
  place_lair_turrets(summon, surface, spawner.position)
  summon.appear_position = util.copy_position(spawner.position)
  return true, nil
end

---The territory of the Host Worm: the generated chunks around the beacon.
---@param surface LuaSurface
---@param center MapPosition
---@return LuaTerritory|nil
local function create_territory(surface, center)
  local origin = util.chunk_of(center)
  local chunks = {}
  for x = origin.x - TERRITORY_CHUNK_RADIUS, origin.x + TERRITORY_CHUNK_RADIUS do
    for y = origin.y - TERRITORY_CHUNK_RADIUS, origin.y + TERRITORY_CHUNK_RADIUS do
      if surface.is_chunk_generated({ x = x, y = y }) then
        chunks[#chunks + 1] = { x = x, y = y }
      end
    end
  end
  if #chunks == 0 then
    return nil
  end
  local ok, territory = pcall(function()
    return surface.create_territory({ chunks = chunks })
  end)
  if ok and territory and territory.valid then
    return territory
  end
  return nil
end

---Orders for the worm: hunt the nearest building of the player, or go to the beacon when there is none.
---@param summon table
---@param surface LuaSurface
---@param worm LuaSegmentedUnit
local function worm_orders(summon, surface, worm)
  local head = worm.get_body_nodes()[1] or summon.position
  local target = nearest_building(surface, head, summon.position, summon.force)
  pcall(function()
    if target then
      worm.set_ai_state({
        type = defines.segmented_unit_ai_state.enraged_at_target,
        target = target,
        attacked_me = true,
        last_damage_time = game.tick,
      })
    else
      worm.set_ai_state({ type = defines.segmented_unit_ai_state.investigating, destination = summon.position })
    end
  end)
end

---@param summon table
---@param surface LuaSurface
---@return boolean ok
---@return string|nil message_key
local function spawn_worm(summon, surface)
  if not prototypes.entity[WORM] then
    return false, "msg-fail-prototype"
  end
  local position = find_position(summon, surface, WORM)
  if not position then
    return false, "msg-fail-position"
  end
  local territory = create_territory(surface, summon.position)
  local ok, worm = pcall(function()
    return surface.create_segmented_unit({
      name = WORM,
      position = position,
      direction = util.direction_toward(position, summon.position),
      force = "enemy",
      territory = territory,
    })
  end)
  if not (ok and worm and worm.valid) then
    if territory and territory.valid then
      territory.destroy()
    end
    return false, "msg-fail-position"
  end
  summon.territory = territory
  -- do not let the engine put a boss to sleep: nobody may be near it for a while
  pcall(function()
    worm.minimum_activity_mode = defines.segmented_unit_activity_mode.minimal
  end)
  records.add(summon, worm, WORM, true, "boss", true)
  summon.appear_position = util.copy_position(position)
  worm_orders(summon, surface, worm)
  return true, nil
end

local SPAWNERS = {
  ["arachnid-queen"] = spawn_queen,
  ["storm-guardian"] = spawn_guardian,
  ["toxic-lair"] = spawn_lair,
  ["host-worm"] = spawn_worm,
}

---Asks the map generator for the ring where the boss will look for its place (SPAWN_MAX around the beacon). The
---generation is asynchronous, so it is asked for when the countdown starts: by the end of it the chunks exist, and
---util.find_spawn_position no longer generates up to 24 of them synchronously in one tick.
---@param surface LuaSurface
---@param position MapPosition the beacon
function M.request_spawn_land(surface, position)
  pcall(function()
    surface.request_to_generate_chunks(position, math.ceil(SPAWN_MAX / 32) + 1)
  end)
end

---Creates the boss of the summon and its followers.
---@param summon table
---@param surface LuaSurface
---@return boolean ok
---@return string|nil message_key why it failed
function M.spawn(summon, surface)
  local spawner = SPAWNERS[summon.boss]
  if not spawner then
    return false, "msg-fail-prototype"
  end
  local ok, message_key = spawner(summon, surface)
  return ok, message_key
end

---New orders for the marching units.
---@param summon table
---@param surface LuaSurface
local function redispatch(summon, surface)
  local units = records.commandable_units(summon)
  if #units == 0 then
    return
  end
  local target = nearest_building(surface, units[1].position, summon.position, summon.force)
  M.dispatch(surface, units, target and util.copy_position(target.position) or summon.position)
end

---@param summon table
local function lair_upkeep(summon)
  local turrets = summon.lair.turrets
  for index = #turrets, 1, -1 do
    local turret = turrets[index]
    if turret.valid then
      arm_turret(summon, turret)
    else
      table.remove(turrets, index)
    end
  end
end

---The units of the lair march out. Every unit gets a command of its own: putting them into a unit group would release
---them from the spawner, which counts only the units it still owns against max_count_of_owned_units and would build
---seven more, again and again.
---@param summon table
---@param surface LuaSurface
local function lair_sortie(summon, surface)
  local spawner = summon.lair.spawner
  if not (spawner and spawner.valid) then
    return
  end
  local target = nearest_building(surface, spawner.position, summon.position, summon.force)
  local destination = target and util.copy_position(target.position) or summon.position
  for _, unit in ipairs(spawner.units) do
    if unit.valid then
      local commandable = unit.commandable
      if commandable then
        commandable.set_command(attack_command(destination))
      end
    end
  end
end

---Called once a second while the summon is active.
---@param summon table
---@param surface LuaSurface
function M.tick(summon, surface)
  local seconds = summon.active_seconds
  local boss = summon.boss
  if boss == "arachnid-queen" or boss == "storm-guardian" then
    if seconds % REDISPATCH_SECONDS == 0 then
      redispatch(summon, surface)
    end
  elseif boss == "toxic-lair" and summon.lair then
    if seconds % LAIR_UPKEEP_SECONDS == 0 then
      lair_upkeep(summon)
    end
    if seconds % LAIR_SORTIE_SECONDS == 0 then
      lair_sortie(summon, surface)
    end
  elseif boss == "host-worm" and seconds % WORM_ORDER_SECONDS == 0 then
    local record = summon.tracked[1]
    if record and not (record.dead or record.gone) and record.entity.valid then
      worm_orders(summon, surface, record.entity)
    end
  end
end

---The boss is dead: what belonged to it goes with it.
---@param summon table
function M.on_victory(summon)
  if summon.lair then
    for _, turret in ipairs(summon.lair.turrets) do
      if turret.valid then
        turret.die(summon.force)
      end
    end
  end
  if summon.territory and summon.territory.valid then
    summon.territory.destroy()
  end
end

---The trial ends without a victory (an administrator stopped it, the boss vanished, an error): what the mod set up for
---it must not stay in a state that only the trial understands. A Host Worm that still lives is allowed to sleep again
---(the minimum activity mode that kept it awake is reset); a territory that guards no segmented unit any more is removed.
---The worm itself stays, untracked, unless the boss entities were destroyed on purpose (destroying a territory destroys
---the segmented units that guard it).
---@param summon table
function M.release(summon)
  for _, record in ipairs(summon.tracked) do
    local worm = record.entity
    if record.segmented and worm and worm.valid then
      pcall(function()
        worm.minimum_activity_mode = nil
      end)
    end
  end
  local territory = summon.territory
  if territory and territory.valid then
    local ok, guards = pcall(function()
      return territory.get_segmented_units()
    end)
    if ok and #guards == 0 then
      territory.destroy()
    end
  end
  summon.territory = nil
end

return M
