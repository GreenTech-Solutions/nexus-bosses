-- Tagged benchmark tests for boss fight duration on the fixed endgame defence base.

local cfg = require("lib.nb_data")
local helpers = require("tests.helpers")

local COUNTDOWN_SECONDS = 30
local MAX_FIGHT_SECONDS = 15 * 60
local AMMO_REFILL_COUNT = 100000
local INTERFACE_POWER_PRODUCTION = 1000000000
local INTERFACE_BUFFER_SIZE = 1000000000
local BASE_CLEAR_RADIUS = 45
local PLACEMENT_STEP = 0.5
local PLACEMENT_MAX_SHIFT = 5
local BEACON_PREFIX = "nexus-summon-"
local COMMANDER_NUKE_SETTING = "nexus-bosses-commander-nuke"
local INFECTED_PREFIX = "tb_infected_"

local SETUP = {
  ["arachnid-queen"] = "base",
  watcher = "base",
  ["rogue-spidertron"] = "base",
  devourer = "base",
  colossus = "siege",
  ["storm-guardian"] = "siege",
  ["last-commander"] = "siege",
  ["plague-hulk"] = "siege",
  ["twin-maws"] = "siege2",
}

local TURRET_RADII = {
  ["gun-turret"] = 12,
  ["laser-turret"] = 16,
  ["rocket-turret"] = 21,
  ["railgun-turret"] = 32,
}

---@type table<integer, defines.direction>
local RAIL_DIRECTIONS = {
  [0] = defines.direction.north,
  [2] = defines.direction.northeast,
  [4] = defines.direction.east,
  [6] = defines.direction.southeast,
  [8] = defines.direction.south,
  [10] = defines.direction.southwest,
  [12] = defines.direction.west,
  [14] = defines.direction.northwest,
}

local MOVE_BOSSES = {
  colossus = true,
  ["storm-guardian"] = true,
  ["last-commander"] = true,
}

-- Each layout is the quarter-stage battery aimed at the boss, as decided for duration measurements.
---@type {name: string, count: integer}[][]
local layouts = {
  { { name = "gun-turret", count = 4 }, { name = "laser-turret", count = 4 } },
  { { name = "gun-turret", count = 6 }, { name = "laser-turret", count = 6 },
    { name = "rocket-turret", count = 2 } },
  { { name = "gun-turret", count = 8 }, { name = "laser-turret", count = 8 },
    { name = "rocket-turret", count = 4 }, { name = "railgun-turret", count = 2 } },
}

local AMMO = {
  ["gun-turret"] = "uranium-rounds-magazine",
  ["rocket-turret"] = "explosive-rocket",
  ["railgun-turret"] = "railgun-ammo",
}

tags("duration")
describe("boss duration", function()
  ---@type LuaSurface|nil
  local surface
  ---@type LuaEntity[]
  local base_entities = {}
  ---@type {name: string, position: MapPosition, direction: defines.direction|nil, ammo: string|nil, entity: LuaEntity, loss_recorded: boolean|nil}[]
  local turrets = {}
  ---@type {name: string, position: MapPosition, entity: LuaEntity, loss_recorded: boolean|nil}[]
  local power_entities = {}
  ---@type {force_name: string, boss_id: string, was_defeated: boolean, had_record: boolean, variant_id: string|nil, was_variant_defeated: boolean}|nil
  local saved_defeat
  local commander_nuke_setting_saved = false
  local commander_nuke_original

  local function restore_commander_nuke_setting()
    if commander_nuke_setting_saved then
      ---@diagnostic disable-next-line: assign-type-mismatch
      -- luacheck: ignore 122
      settings.global[COMMANDER_NUKE_SETTING] = { value = commander_nuke_original }
      commander_nuke_setting_saved = false
      commander_nuke_original = nil
    end
  end

  local function clear_base()
    for _, entity in ipairs(base_entities) do
      if entity.valid then
        entity.destroy()
      end
    end
    base_entities = {}
    turrets = {}
    power_entities = {}
  end

  ---@param name string
  ---@param position MapPosition
  ---@param direction defines.direction|nil
  ---@param player LuaPlayer
  ---@return LuaEntity
  local function create_base_entity(name, position, direction, player)
    local current_surface = assert(surface, "the Nexus surface has not been prepared")
    local spec = { name = name, position = position, force = player.force }
    if direction then
      spec.direction = direction
    end
    local entity = current_surface.create_entity(spec)
    assert(entity, string.format("could not create %s at (%.1f, %.1f)", name, position.x, position.y))
    entity.last_user = player
    base_entities[#base_entities + 1] = entity
    return entity
  end

  ---@param entity LuaEntity
  local function configure_interface(entity)
    entity.power_production = INTERFACE_POWER_PRODUCTION
    entity.electric_buffer_size = INTERFACE_BUFFER_SIZE
    entity.energy = INTERFACE_BUFFER_SIZE
  end

  ---@param name string
  ---@param position MapPosition
  ---@param entity LuaEntity
  local function track_power_entity(name, position, entity)
    power_entities[#power_entities + 1] = {
      name = name,
      position = position,
      entity = entity,
    }
  end

  ---@param name string
  ---@param position MapPosition
  ---@param direction defines.direction|nil
  ---@param center MapPosition
  ---@param player LuaPlayer
  ---@return LuaEntity
  local function create_base_entity_near(name, position, direction, center, player)
    local current_surface = assert(surface, "the Nexus surface has not been prepared")
    local position_x = assert(position.x)
    local position_y = assert(position.y)
    local function try_place(candidate)
      local candidate_direction = direction
      if name == "railgun-turret" then
        local center_x = assert(center.x)
        local center_y = assert(center.y)
        local x = assert(candidate.x)
        local y = assert(candidate.y)
        local direction_value = (math.floor(math.atan2(center_x - x, -(center_y - y)) / (math.pi / 4) + 0.5) % 8) * 2
        candidate_direction = RAIL_DIRECTIONS[direction_value]
      end
      local placement = { name = name, position = candidate, force = player.force }
      if candidate_direction then
        placement.direction = candidate_direction
      end
      if not current_surface.can_place_entity(placement) then
        return nil
      end
      return create_base_entity(name, candidate, candidate_direction, player)
    end

    local entity = try_place(position)
    if entity then
      return entity
    end
    for radius = PLACEMENT_STEP, PLACEMENT_MAX_SHIFT, PLACEMENT_STEP do
      local points = math.ceil(2 * math.pi * radius / PLACEMENT_STEP)
      for index = 0, points - 1 do
        local angle = 2 * math.pi * index / points
        local candidate = {
          x = position_x + math.cos(angle) * radius,
          y = position_y + math.sin(angle) * radius,
        }
        entity = try_place(candidate)
        if entity then
          return entity
        end
      end
    end
    error(string.format("could not create %s at (%.1f, %.1f)", name, position.x, position.y))
  end

  ---@param turret {entity: LuaEntity, ammo: string|nil}
  local function refill(turret)
    if turret.ammo and turret.entity.valid then
      turret.entity.insert({ name = turret.ammo, count = AMMO_REFILL_COUNT })
    end
  end

  ---@param summon table|nil
  ---@param losses table
  ---@param power_losses table
  local function restore_destroyed_turrets(summon, losses, power_losses)
    local current_surface = assert(surface, "the Nexus surface has not been prepared")
    local player = assert(game.get_player(1), "the first test player is missing")
    local tracked_units = {}
    for _, record in ipairs(summon and summon.tracked or {}) do
      if record.unit_number then
        tracked_units[record.unit_number] = true
      end
    end

    for _, slot in ipairs(turrets) do
      if not slot.entity.valid then
        if not slot.loss_recorded then
          losses.count = losses.count + 1
          slot.loss_recorded = true
        end
        for _, entity in ipairs(current_surface.find_entities_filtered({ position = slot.position, radius = 2 })) do
          local is_ghost = entity.name == "entity-ghost"
          local is_untracked_infected = entity.force and entity.force.name == "enemy"
            and string.sub(entity.name, 1, #INFECTED_PREFIX) == INFECTED_PREFIX
            and not (entity.unit_number and tracked_units[entity.unit_number])
          if is_ghost or is_untracked_infected then
            entity.destroy()
          end
        end
        local entity = current_surface.create_entity({
          name = slot.name,
          position = slot.position,
          direction = slot.direction,
          force = player.force,
        })
        if entity then
          entity.last_user = player
          slot.entity = entity
          slot.loss_recorded = false
          base_entities[#base_entities + 1] = entity
          refill(slot)
        end
      end
    end

    for _, slot in ipairs(power_entities) do
      if not slot.entity.valid then
        if not slot.loss_recorded then
          power_losses.count = power_losses.count + 1
          slot.loss_recorded = true
        end
        for _, entity in ipairs(current_surface.find_entities_filtered({ position = slot.position, radius = 2 })) do
          local is_ghost = entity.name == "entity-ghost"
          local is_untracked_infected = entity.force and entity.force.name == "enemy"
            and string.sub(entity.name, 1, #INFECTED_PREFIX) == INFECTED_PREFIX
            and not (entity.unit_number and tracked_units[entity.unit_number])
          if is_ghost or is_untracked_infected then
            entity.destroy()
          end
        end
        local entity
        if slot.name == "electric-energy-interface" then
          entity = create_base_entity(slot.name, slot.position, nil, player)
          configure_interface(entity)
        else
          entity = create_base_entity_near(slot.name, slot.position, nil, slot.position, player)
          slot.position = entity.position
        end
        entity.last_user = player
        slot.entity = entity
        slot.loss_recorded = false
      end
    end
  end

  ---@param center MapPosition
  ---@param summon table|nil
  local function clear_base_area(center, summon)
    local current_surface = assert(surface, "the Nexus surface has not been prepared")
    local center_x = assert(center.x)
    local center_y = assert(center.y)
    current_surface.request_to_generate_chunks(center, 3)
    current_surface.force_generate_chunk_requests()
    local tracked_units = {}
    for _, record in ipairs(summon and summon.tracked or {}) do
      if record.unit_number then
        tracked_units[record.unit_number] = true
      end
    end
    local left_x = math.floor(center_x - BASE_CLEAR_RADIUS)
    local top_y = math.floor(center_y - BASE_CLEAR_RADIUS)
    local right_x = math.ceil(center_x + BASE_CLEAR_RADIUS)
    local bottom_y = math.ceil(center_y + BASE_CLEAR_RADIUS)
    local area = {
      left_top = { x = left_x, y = top_y },
      right_bottom = { x = right_x, y = bottom_y },
    }
    for _, entity in ipairs(current_surface.find_entities_filtered({ area = area })) do
      local is_beacon = string.sub(entity.name, 1, #BEACON_PREFIX) == BEACON_PREFIX
      local is_character = entity.type == "character"
      local is_enemy = entity.force and entity.force.name == "enemy"
      local is_tracked = entity.unit_number and tracked_units[entity.unit_number]
      if entity.valid and not is_beacon and not is_character and not is_enemy and not is_tracked then
        entity.destroy()
      end
    end

    current_surface.destroy_decoratives({ area = area })
    local tiles = {}
    for x = left_x, right_x - 1 do
      for y = top_y, bottom_y - 1 do
        tiles[#tiles + 1] = { name = "refined-concrete", position = { x = x, y = y } }
      end
    end
    current_surface.set_tiles(tiles, true, false, false, false)
  end

  ---@param circle integer
  ---@param center MapPosition
  ---@param summon table|nil
  ---@param split boolean|nil
  ---@param clean_area boolean|nil
  local function build_base(circle, center, summon, split, clean_area)
    local layout = layouts[circle]
    if not layout then
      error("there is no defence layout for circle " .. circle)
    end
    local center_x = assert(center.x)
    local center_y = assert(center.y)
    local player = assert(game.get_player(1), "the first test player is missing")

    if clean_area ~= false then
      clear_base_area(center, summon)
    end

    -- The centre is occupied by the beacon or boss; the interface is placed beside the +18 substation.
    for x = -36, 36, 18 do
      for y = -36, 36, 18 do
        if x ~= 0 or y ~= 0 then
          local position = { x = center_x + x, y = center_y + y }
          local entity = create_base_entity_near("substation", position, nil, center, player)
          track_power_entity("substation", entity.position, entity)
        end
      end
    end

    local first_turret_index = #turrets + 1
    for _, entry in ipairs(layout) do
      local count = split and math.ceil(entry.count / 2) or entry.count
      local radius = assert(TURRET_RADII[entry.name])
      for index = 0, count - 1 do
        local angle = 2 * math.pi * index / count
        local position = { x = center_x + radius * math.cos(angle), y = center_y + radius * math.sin(angle) }
        local entity = create_base_entity_near(entry.name, position, nil, center, player)
        local turret = {
          name = entry.name,
          position = entity.position,
          direction = entity.direction,
          ammo = AMMO[entry.name],
          entity = entity,
        }
        turrets[#turrets + 1] = turret
        refill(turret)
      end
    end

    local interface = create_base_entity("electric-energy-interface", { x = center_x + 18, y = center_y + 4 },
      nil, player)
    configure_interface(interface)
    track_power_entity("electric-energy-interface", interface.position, interface)

    local interface_network = interface.electric_network_id
    if not interface_network then
      error(string.format("electric-energy-interface at (%.1f, %.1f) has no electric network",
        interface.position.x, interface.position.y))
    end
    for index = first_turret_index, #turrets do
      local turret = turrets[index]
      if turret.name == "laser-turret" or turret.name == "railgun-turret" then
        if turret.entity.electric_network_id ~= interface_network then
          error(string.format("%s at (%.1f, %.1f) is not connected to the base electric network",
            turret.name, turret.position.x, turret.position.y))
        end
      end
    end
  end

  ---@return integer
  local function live_turret_count()
    local count = 0
    for _, turret in ipairs(turrets) do
      if turret.entity.valid then
        count = count + 1
      end
    end
    return count
  end

  ---@return integer
  local function powered_turret_count()
    local count = 0
    for _, turret in ipairs(turrets) do
      if turret.entity.valid and (turret.name == "laser-turret" or turret.name == "railgun-turret")
        and turret.entity.energy > 0 then
        count = count + 1
      end
    end
    return count
  end

  ---@param boss_id string
  ---@param seconds integer
  ---@param health_share number
  ---@param outcome string
  ---@param first_hit integer
  ---@param losses integer
  ---@param moves integer
  ---@param feed integer
  ---@param power_losses integer
  local function log_result(boss_id, seconds, health_share, outcome, first_hit, losses, moves, feed, power_losses)
    log(string.format("nexus-bosses DURATION %s %d %.2f %s first_hit=%d losses=%d moves=%d feed=%d power_losses=%d",
      boss_id, seconds, health_share, outcome, first_hit, losses, moves, feed, power_losses))
  end

  ---@param summon table
  ---@param boss_id string
  ---@return MapPosition|nil center, MapPosition|nil main_position
  local function boss_positions(summon, boss_id)
    local positions = {}
    for _, record in ipairs(summon.tracked or {}) do
      if record.role == "boss" and not record.dead and not record.gone and record.position then
        positions[#positions + 1] = record.position
      end
    end
    if #positions == 0 then
      return nil, nil
    end
    if boss_id == "twin-maws" and #positions >= 2 then
      return {
        x = (positions[1].x + positions[2].x) / 2,
        y = (positions[1].y + positions[2].y) / 2,
      }, positions[1]
    end
    return positions[1], positions[1]
  end

  ---@param boss_id string
  ---@param summon table
  ---@return number|nil
  local function nearest_turret_distance(boss_id, summon)
    local _, main_position = boss_positions(summon, boss_id)
    if not main_position then
      return nil
    end
    local main_x = assert(main_position.x)
    local main_y = assert(main_position.y)
    local nearest
    for _, turret in ipairs(turrets) do
      if turret.entity.valid then
        local x = assert(turret.entity.position.x)
        local y = assert(turret.entity.position.y)
        local dx = x - main_x
        local dy = y - main_y
        local distance = math.sqrt(dx * dx + dy * dy)
        if not nearest or distance < nearest then
          nearest = distance
        end
      end
    end
    return nearest
  end

  ---@return number, integer
  local function laser_energy()
    ---@type number
    local total = 0
    local count = 0
    for _, turret in ipairs(turrets) do
      if turret.entity.valid and turret.entity.name == "laser-turret" then
        total = total + turret.entity.energy
        count = count + 1
      end
    end
    return count > 0 and total / count or 0, count
  end

  ---@return integer
  local function empty_ammo_turrets()
    local count = 0
    for _, turret in ipairs(turrets) do
      if turret.ammo and turret.entity.valid and turret.entity.get_item_count(turret.ammo) == 0 then
        count = count + 1
      end
    end
    return count
  end

  ---@param boss_id string
  ---@param summon table
  ---@param seconds integer
  ---@param health_share number
  ---@param losses integer
  ---@param power_losses integer
  local function log_trace(boss_id, summon, seconds, health_share, losses, power_losses)
    local energy = laser_energy()
    local min_dist = nearest_turret_distance(boss_id, summon)
    log(string.format("nexus-bosses DURATION-TRACE %s t=%d health=%.2f turrets=%d min_dist=%s laser_energy=%.0f ammo=%d losses=%d powered=%d power_losses=%d",
      boss_id, seconds, health_share, live_turret_count(), min_dist and string.format("%.1f", min_dist) or "n/a",
      energy, empty_ammo_turrets(), losses, powered_turret_count(), power_losses))
  end

  ---@param boss_id string
  ---@param message any
  local function log_error(boss_id, message)
    log(string.format("nexus-bosses DURATION %s ERROR %s", boss_id, tostring(message)))
  end

  before_each(function()
    clear_base()
    helpers.reset()
    surface = helpers.nexus()
    game.forces.player.research_all_technologies()
    remote.call("nexus-bosses", "set_ignore_player_presence", true)
    remote.call("nexus-bosses", "set_countdown", COUNTDOWN_SECONDS)
  end)

  after_each(function()
    restore_commander_nuke_setting()
    clear_base()
    helpers.reset()
    remote.call("nexus-bosses", "set_countdown", nil)
    remote.call("nexus-bosses", "set_ignore_player_presence", false)

    if saved_defeat then
      local record = storage.progress[saved_defeat.force_name]
      if record then
        record.defeated[saved_defeat.boss_id] = saved_defeat.was_defeated and true or nil
        if saved_defeat.variant_id then
          record.colossus_variants = record.colossus_variants or {}
          record.colossus_variants[saved_defeat.variant_id] = saved_defeat.was_variant_defeated and true or nil
          if next(record.colossus_variants) == nil then
            record.colossus_variants = nil
          end
        end
        if not saved_defeat.had_record and next(record.defeated) == nil and not record.colossus_variants then
          storage.progress[saved_defeat.force_name] = nil
        end
      end
      saved_defeat = nil
    end
  end)

  ---@param test_name string
  ---@param boss_id string
  ---@param variant_id string|nil
  local function register_duration_test(test_name, boss_id, variant_id)
    local setup = assert(SETUP[boss_id], "missing duration setup for " .. boss_id)
    test(test_name, function()
      local force = game.forces.player
      local boss = cfg.BOSSES[boss_id]
      local log_id = variant_id and ("colossus-" .. variant_id) or boss_id
      local prepare_ok, prepare_message = pcall(function()
        local progress_record = storage.progress[force.name] --[[@as {defeated: table<string, boolean>, colossus_variants: table<string, boolean>|nil}|nil]]
        saved_defeat = {
          force_name = force.name,
          boss_id = boss_id,
          was_defeated = progress_record ~= nil and progress_record.defeated[boss_id] == true,
          had_record = progress_record ~= nil,
          variant_id = variant_id,
          was_variant_defeated = variant_id ~= nil and progress_record ~= nil
            and progress_record.colossus_variants ~= nil and progress_record.colossus_variants[variant_id] == true,
        }
        if progress_record then
          progress_record.defeated[boss_id] = nil
        end

        if setup ~= "base" then
          remote.call("nexus-bosses", "set_countdown", 3)
        end
        if boss_id == "last-commander" then
          local setting = settings.global[COMMANDER_NUKE_SETTING]
          commander_nuke_original = setting and setting.value
          commander_nuke_setting_saved = true
          after_test(restore_commander_nuke_setting)
          ---@diagnostic disable-next-line: assign-type-mismatch
          -- luacheck: ignore 122
          settings.global[COMMANDER_NUKE_SETTING] = { value = false }
        end
        if variant_id then
          remote.call("nexus-bosses", "set_next_colossus", variant_id)
        end

        if setup == "base" then
          build_base(boss.circle, { x = 0, y = 0 })
        end
        helpers.light(boss_id, { x = 0, y = 0 })
      end)
      if not prepare_ok then
        log_error(log_id, prepare_message)
        restore_commander_nuke_setting()
        remote.call("nexus-bosses", "set_countdown", nil)
        error(prepare_message, 0)
      end

      local started_at
      local center = setup == "base" and { x = 0, y = 0 } or nil
      local next_refill = game.tick + 10 * 60
      local last_health_share = 1
      local first_hit = -1
      local feed_seconds = 0
      local last_feed_second = -1
      local next_trace_seconds = 10
      local losses = { count = 0 }
      local power_losses = { count = 0 }
      local moves = 0
      local parts_logged = {}
      local part_count = 0
      local distance_out_since
      local initial_summon = helpers.active()
      local last_phase = initial_summon and initial_summon.phase or "none"
      local last_beacon_valid = initial_summon and initial_summon.beacon_valid or false
      local last_spawn_note = initial_summon and initial_summon.spawn_note or "none"
      local timeout_ticks = (COUNTDOWN_SECONDS + MAX_FIGHT_SECONDS + 15) * 60
      local test_started_at = game.tick

      local function finish(outcome, seconds, health_share)
        log_result(log_id, seconds, health_share, outcome, first_hit, losses.count, moves, feed_seconds,
          power_losses.count)
        restore_commander_nuke_setting()
        remote.call("nexus-bosses", "set_countdown", nil)
        done()
      end

      async(timeout_ticks + 60)
      on_tick(function()
        local tick_ok, tick_result = pcall(function()
          while game.tick >= next_refill do
            for _, turret in ipairs(turrets) do
              refill(turret)
            end
            next_refill = next_refill + 10 * 60
          end
          local summon = helpers.active()
          if summon then
            last_phase = summon.phase or "none"
            last_beacon_valid = summon.beacon_valid == true
            last_spawn_note = summon.spawn_note or "none"
          end

          restore_destroyed_turrets(summon, losses, power_losses)
          if not summon and not started_at then
            error(string.format("the %s summon ended during the countdown: phase=%s beacon_valid=%s spawn_note=%s",
              boss_id, tostring(last_phase), tostring(last_beacon_valid), tostring(last_spawn_note)))
          end

          if summon and summon.phase == "active" then
            if not started_at then
              if setup == "siege" then
                local boss_center = boss_positions(summon, boss_id)
                if not boss_center then
                  error("the " .. boss_id .. " main record has no position after becoming active")
                end
                center = boss_center
                build_base(boss.circle, center, summon)
              elseif setup == "siege2" then
                local maw_positions = {}
                for _, record in ipairs(summon.tracked or {}) do
                  if record.role == "boss" and not record.dead and not record.gone and record.position then
                    maw_positions[#maw_positions + 1] = record.position
                  end
                end
                if #maw_positions < 2 then
                  error("Twin Maws did not expose both positions after becoming active")
                end
                center = {
                  x = (maw_positions[1].x + maw_positions[2].x) / 2,
                  y = (maw_positions[1].y + maw_positions[2].y) / 2,
                }
                clear_base_area(center, summon)
                build_base(boss.circle, maw_positions[1], summon, true, false)
                build_base(boss.circle, maw_positions[2], summon, true, false)
              end
              started_at = game.tick
              next_refill = game.tick + 10 * 60
            end

            last_health_share = summon.health_share or last_health_share
            local seconds = math.floor((game.tick - started_at) / 60)
            if boss_id == "storm-guardian" and seconds > last_feed_second then
              last_feed_second = seconds
              if summon.boss_state and summon.boss_state.feeding == true then
                feed_seconds = feed_seconds + 1
              end
            end
            if first_hit < 0 and last_health_share < 0.999 then
              first_hit = seconds
            end

            while seconds >= next_trace_seconds do
              log_trace(log_id, summon, next_trace_seconds, last_health_share, losses.count, power_losses.count)
              next_trace_seconds = next_trace_seconds + 10
            end

            if setup == "siege" and MOVE_BOSSES[boss_id] and moves < 20 and center then
              local _, main_position = boss_positions(summon, boss_id)
              if main_position then
                local main_x = assert(main_position.x)
                local main_y = assert(main_position.y)
                local center_x = assert(center.x)
                local center_y = assert(center.y)
                local dx = main_x - center_x
                local dy = main_y - center_y
                if math.sqrt(dx * dx + dy * dy) > 15 then
                  distance_out_since = distance_out_since or game.tick
                  if game.tick - distance_out_since >= 10 * 60 then
                    clear_base()
                    center = main_position
                    build_base(boss.circle, center, summon)
                    moves = moves + 1
                    distance_out_since = nil
                    next_refill = game.tick + 10 * 60
                  end
                else
                  distance_out_since = nil
                end
              end
            end
          end

          if boss_id == "twin-maws" and started_at and summon then
            local seconds = math.floor((game.tick - started_at) / 60)
            for _, record in ipairs(summon.tracked or {}) do
              if record.role == "boss" and record.dead and not parts_logged[record.name] then
                parts_logged[record.name] = true
                part_count = part_count + 1
                log(string.format("nexus-bosses DURATION-PART twin-maws %s %d", record.name, seconds))
              end
            end
          end

          local state = remote.call("nexus-bosses", "get_state")
          if state and state.defeated[force.name] and state.defeated[force.name][boss_id] then
            finish("victory", started_at and math.floor((game.tick - started_at) / 60) or 0, 0)
            return false
          end
          if boss_id == "twin-maws" and part_count >= 2 then
            finish("parts", math.floor((game.tick - assert(started_at)) / 60), last_health_share)
            return false
          end
          if started_at and (not summon or summon.phase ~= "active") then
            error("the " .. boss_id .. " summon ended without a victory")
          end
          if started_at and game.tick - started_at >= MAX_FIGHT_SECONDS * 60 then
            finish("limit", MAX_FIGHT_SECONDS, last_health_share)
            return false
          end
          if game.tick - test_started_at >= timeout_ticks then
            error("the " .. boss_id .. " duration test timed out")
          end
        end)
        if not tick_ok then
          log_error(log_id, tick_result)
          restore_commander_nuke_setting()
          remote.call("nexus-bosses", "set_countdown", nil)
          error(tick_result, 0)
        end
        return tick_result
      end)
    end)
  end

  for _, id in ipairs(cfg.ORDER) do
    if id ~= "colossus" then
      register_duration_test("duration " .. id, id, nil)
    end
  end
  for _, variant in ipairs(cfg.COLOSSUS_VARIANTS) do
    register_duration_test("duration colossus " .. variant.id, "colossus", variant.id)
  end
end)
