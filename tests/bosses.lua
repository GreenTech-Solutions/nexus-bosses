-- Tests for boss mechanics using headless summon snapshots.

local helpers = require("tests.helpers")
local util = require("scripts.nb_util")

---@param surface LuaSurface
---@param name string
---@param position MapPosition
---@param radius number|nil
---@return LuaEntity
local function player_entity_at(surface, name, position, radius)
  local spot = surface.find_non_colliding_position(name, position, radius or 8, 1)
  assert(spot, "there was no clear spot for the test " .. name)
  local entity = surface.create_entity({ name = name, position = spot, force = "player" })
  assert(entity, "the test " .. name .. " could not be created")
  return entity
end

---@param surface LuaSurface
---@param position MapPosition
---@return LuaEntity
local function wall_at(surface, position)
  local place = surface.find_non_colliding_position("stone-wall", position, 8, 1)
  assert(place, "there was no clear spot for the test wall")
  local wall = surface.create_entity({ name = "stone-wall", position = place, force = "player" })
  assert(wall, "the test wall could not be created")
  return wall
end

---@param summon table|nil
---@param wall LuaEntity|nil
---@return string
local function describe_watcher_timeout(summon, wall)
  local wall_alive = wall and wall.valid
  local wall_health
  if wall_alive then
    ---@cast wall LuaEntity
    wall_health = wall.health
  end
  local pending_details = {}
  local pending_data = remote.call("nexus-bosses", "get_pending_data")
  ---@cast pending_data {kind: string, at: integer, data: table}[]
  for _, detail in ipairs(pending_data) do
    local position = detail.data.position
    local position_text = position and string.format("(%s,%s)", tostring(position.x), tostring(position.y))
      or "nil"
    pending_details[#pending_details + 1] = string.format("kind=%s target=%s position=%s",
      tostring(detail.kind), tostring(detail.data.target), position_text)
  end
  return helpers.describe_summon(summon)
    .. string.format(" wall_alive=%s wall_health=%s pending=[%s]", tostring(wall_alive),
      tostring(wall_health), table.concat(pending_details, "; "))
end

describe("reworked bosses", function()
  before_each(function()
    helpers.reset()
    helpers.nexus()
  end)

  test("the Watcher strike damages a nearby player building", function()
    local surface = helpers.nexus()
    helpers.light("watcher", { 0, 0 })
    local strike_at
    local wall
    local wall_health
    helpers.on_active(2400, function(summon, ticks_since_active)
      if wall and not strike_at and not wall.valid then
        error("the test wall died before the Watcher marked it")
      end
      if not wall then
        local boss = helpers.tracked(summon, "boss")
        assert(boss and boss.position, "the Watcher position is missing from the summon snapshot")
        assert(helpers.role_count(summon, "boss") == 1 and helpers.role_count(summon, "escort") == 6,
          "the Watcher should appear with one boss and six escort drones")
        wall = wall_at(surface, { x = boss.position.x + 40, y = boss.position.y })
        wall.destructible = false
      end
      if wall and not strike_at then
        local strike = helpers.pending(summon, "strike")
        if strike then
          local pending_data = remote.call("nexus-bosses", "get_pending_data")
          ---@cast pending_data {kind: string, at: integer, data: table}[]
          for _, detail in ipairs(pending_data) do
            if helpers.role_count(summon, "escort") > 0 and detail.kind == "strike" and detail.at == strike.at
              and detail.data.target == wall.unit_number then
              strike_at = detail.at
              wall.destructible = true
              wall_health = wall.health
              assert(wall_health, "the Watcher test wall has no health when marked")
              break
            end
          end
        end
      elseif strike_at and game.tick >= strike_at + 4 * 60 then
        ---@cast wall LuaEntity
        ---@cast wall_health number
        local damaged = not wall.valid
        if wall.valid then
          local current_health = wall.health
          damaged = current_health ~= nil and current_health < wall_health - 1
        end
        assert(damaged, "the Watcher's queued strike did not damage the marked wall")
        return true
      end
      if ticks_since_active >= 2400 then
        error("the Watcher did not damage the test wall in time: " .. describe_watcher_timeout(summon, wall))
      end
    end)
  end)

  test("the Watcher cancels a queued strike when its drones die", function()
    local surface = helpers.nexus()
    helpers.light("watcher", { 0, 0 })
    local wall
    local wall_health
    local strike_at
    helpers.on_active(1400, function(summon, ticks_since_active)
      if not wall then
        local boss = helpers.tracked(summon, "boss")
        assert(boss and boss.position, "the Watcher position is missing from the summon snapshot")
        assert(helpers.role_count(summon, "boss") == 1 and helpers.role_count(summon, "escort") == 6,
          "the Watcher should appear with one boss and six escort drones")
        wall = wall_at(surface, { x = boss.position.x + 40, y = boss.position.y })
        wall.destructible = false
      elseif wall and not strike_at then
        local strike = helpers.pending(summon, "strike")
        if strike then
          strike_at = strike.at
          wall.destructible = true
          wall_health = wall.health
          assert(wall_health, "the Watcher cancellation test wall has no health when marked")
          ---@cast summon table
          for _, record in ipairs(summon.tracked) do
            if record.role == "escort" and not record.dead and not record.gone then
              local drone = helpers.find_entity(surface, record.name, record.position, 1)
              if drone and drone.valid then
                drone.die()
              end
            end
          end
        end
      elseif strike_at and game.tick >= strike_at + 20 then
        ---@cast wall LuaEntity
        ---@cast wall_health number
        assert(wall.valid, "the Watcher fired its queued strike after all drones had died")
        local current_health = wall.health
        assert(current_health and math.abs(current_health - wall_health) <= 1,
          "the Watcher fired its queued strike after all drones had died")
        return true
      end
      if ticks_since_active >= 1400 then
        error("the Watcher strike cancellation test timed out: " .. describe_watcher_timeout(summon, wall))
      end
    end)
  end)

  test("the Rogue Spidertron's EMP disables and restores nearby player buildings", function()
    local surface = helpers.nexus()
    helpers.light("rogue-spidertron", { 0, 0 })
    local machine
    local disabled_at
    helpers.on_active(1900, function(summon, ticks_since_active)
      if not machine then
        local boss = helpers.tracked(summon, "boss")
        assert(boss and boss.position, "the Rogue Spidertron position is missing from the summon snapshot")
        local pole_position = surface.find_non_colliding_position("small-electric-pole", {
          x = boss.position.x + 5, y = boss.position.y,
        }, 8, 1)
        assert(pole_position, "there was no clear spot for the test power pole")
        local pole = surface.create_entity({
          name = "small-electric-pole",
          position = pole_position,
          force = "player",
        })
        assert(pole, "the test power pole could not be created")
        local machine_position = surface.find_non_colliding_position("assembling-machine-1", pole.position, 8, 1)
        assert(machine_position, "there was no clear spot for the test machine")
        machine = surface.create_entity({
          name = "assembling-machine-1",
          position = machine_position,
          force = "player",
        })
        assert(machine, "the test machine could not be created")
        local entity = helpers.find_entity(surface, boss.name, boss.position, 5)
        assert(entity and entity.valid and entity.teleport({ x = boss.position.x + 1, y = boss.position.y }),
          "the Rogue Spidertron could not be moved into EMP range")
      elseif machine and not disabled_at and machine.valid and machine.disabled_by_script then
        disabled_at = game.tick
      elseif disabled_at and game.tick >= disabled_at + 960 then
        ---@cast machine LuaEntity
        assert(machine.valid and not machine.disabled_by_script, "the EMP did not restore the test machine")
        return true
      end
      if ticks_since_active >= 1900 then
        error("the Rogue Spidertron EMP test timed out")
      end
    end)
  end)

  test("the Rogue Spidertron chooses the pole with the busiest EMP area", function()
    local surface = helpers.nexus()
    helpers.light("rogue-spidertron", { 0, 0 })
    local poles_ready = false
    ---@type LuaEntity|nil
    local near_pole
    ---@type LuaEntity|nil
    local busy_pole
    helpers.on_active(1200, function(summon, ticks_since_active)
      if not poles_ready then
        local boss = helpers.tracked(summon, "boss")
        assert(boss and boss.position, "the Rogue Spidertron position is missing from the summon snapshot")
        near_pole = player_entity_at(surface, "small-electric-pole",
          { x = boss.position.x + 6, y = boss.position.y })
        busy_pole = player_entity_at(surface, "small-electric-pole",
          { x = boss.position.x + 28, y = boss.position.y })
        local busy_x, busy_y = util.xy(busy_pole.position)
        for _, offset in ipairs({ { -6, -6 }, { 6, -6 }, { -6, 6 }, { 6, 6 }, { 0, 8 } }) do
          player_entity_at(surface, "assembling-machine-1", {
            x = busy_x + offset[1],
            y = busy_y + offset[2],
          }, 2)
        end
        poles_ready = true
      else
        local target = summon.boss_state and summon.boss_state.target_position --[[@as MapPosition|nil]]
        if target then
          if not (busy_pole and near_pole) then
            error("the Rogue Spidertron pole test lost a test pole")
          end
          local busy_x, busy_y = util.xy(busy_pole.position)
          local near_x, near_y = util.xy(near_pole.position)
          local target_x, target_y = util.xy(target)
          assert(math.abs(target_x - busy_x) <= 0.1 and math.abs(target_y - busy_y) <= 0.1,
            "the Rogue Spidertron did not choose the pole with five nearby assemblers")
          assert((target_x - near_x) ^ 2 + (target_y - near_y) ^ 2 > 100,
            "the Rogue Spidertron chose the isolated nearby pole")
          return true
        end
      end
      if ticks_since_active >= 1200 then
        error("the Rogue Spidertron did not select a pole in time")
      end
    end)
  end)

  test("the Rogue Spidertron approaches the beacon until a pole enters its search radius", function()
    local surface = helpers.nexus()
    helpers.light("rogue-spidertron", { 0, 0 })
    local initial_distance
    local pole
    local movement_checked = false
    helpers.on_active(5 * 60 * 60, function(summon, ticks_since_active)
      local boss = helpers.tracked(summon, "boss")
      assert(boss and boss.position, "the Rogue Spidertron position is missing from the summon snapshot")
      local entity = helpers.find_entity(surface, boss.name, boss.position, 5)
      assert(entity and entity.valid, "the Rogue Spidertron entity is missing")

      if not initial_distance then
        initial_distance = util.distance(boss.position, summon.beacon_position)
        local dx, dy = util.xy(boss.position)
        local beacon_x, beacon_y = util.xy(summon.beacon_position)
        local length = util.distance(boss.position, summon.beacon_position)
        assert(length > 0, "the Rogue Spidertron spawned on the beacon")
        local position = {
          x = beacon_x - (dx - beacon_x) / length * 70,
          y = beacon_y - (dy - beacon_y) / length * 70,
        }
        pole = player_entity_at(surface, "substation", position, 8)
        pole.destructible = false
        assert(util.distance(boss.position, pole.position) > 200,
          "the test substation must start outside the Rogue Spidertron search radius")
      end

      if not movement_checked and ticks_since_active >= 30 * 60 then
        assert(util.distance(boss.position, summon.beacon_position) < initial_distance,
          "the Rogue Spidertron did not approach the beacon during the first 30 seconds")
        movement_checked = true
      end

      local target = summon.boss_state and summon.boss_state.target_position --[[@as MapPosition|nil]]
      if movement_checked and target and pole then
        local target_x, target_y = util.xy(target)
        local pole_x, pole_y = util.xy(pole.position)
        assert(math.abs(target_x - pole_x) <= 0.1 and math.abs(target_y - pole_y) <= 0.1,
          "the Rogue Spidertron selected a target other than the beacon substation")
        return true
      end

      if ticks_since_active >= 5 * 60 * 60 then
        error("the Rogue Spidertron did not reach and select the beacon substation")
      end
    end)
  end)

  test("the Plague Hulk's spores disable and restore a turret in the marked circle", function()
    local surface = helpers.nexus()
    helpers.light("plague-hulk", { 0, 0 })
    helpers.defend()
    local approach_turret
    local turret
    local disabled_at
    local sortie_units = {}
    local spores_record = false
    local timeout_ticks = (2 * 120 + 30) * 60
    helpers.on_active(timeout_ticks, function(summon, ticks_since_active)
      if ticks_since_active >= 115 * 60 then
        if helpers.pending(summon, "spores") then
          spores_record = true
        end
        for _, sortie_second in ipairs({ 120, 240 }) do
          if ticks_since_active >= sortie_second * 60 and sortie_units[sortie_second] == nil then
            local boss = helpers.tracked(summon, "boss")
            local hulk = boss and boss.position and helpers.find_entity(surface, boss.name, boss.position, 8)
            sortie_units[sortie_second] = hulk and hulk.valid and #hulk.units or 0
          end
        end
      end
      if not approach_turret then
        local boss = helpers.tracked(summon, "boss")
        assert(boss and boss.position, "the Plague Hulk position is missing from the summon snapshot")
        approach_turret = player_entity_at(surface, "gun-turret",
          { x = boss.position.x + 20, y = boss.position.y })
        approach_turret.destructible = false
      elseif not turret then
        local spore = helpers.pending(summon, "spores")
        if spore then
          local pending_data = remote.call("nexus-bosses", "get_pending_data")
          ---@cast pending_data {kind: string, at: integer, data: {position: MapPosition}}[]
          for _, entry in ipairs(pending_data) do
            if entry.kind == "spores" and entry.at == spore.at then
              turret = player_entity_at(surface, "gun-turret", entry.data.position, 4)
              turret.destructible = false
              break
            end
          end
          if not turret then
            error("the Plague Hulk spore warning had no position")
          end
        end
      elseif turret and turret.valid and not disabled_at and turret.disabled_by_script then
        disabled_at = game.tick
      elseif disabled_at and game.tick >= disabled_at + 15 * 60 + 20 then
        ---@cast turret LuaEntity
        assert(turret.valid and not turret.disabled_by_script,
          "the Plague Hulk did not restore the turret after 15 seconds")
        return true
      end
      if ticks_since_active >= timeout_ticks - 600 then
        error(string.format("the Plague Hulk spore test timed out: sortie_units_120=%s sortie_units_240=%s spores_record=%s %s",
          tostring(sortie_units[120]), tostring(sortie_units[240]), tostring(spores_record),
          helpers.describe_summon(summon)))
      end
    end)
  end)

  test("the Plague Hulk has no spores if its sortie dies before approaching", function()
    local surface = helpers.nexus()
    helpers.light("plague-hulk", { 0, 0 })
    helpers.defend()
    local approach_turret = player_entity_at(surface, "gun-turret", { x = 20, y = 0 })
    approach_turret.destructible = false
    local killed = false
    local spores_seen = false
    local killed_at
    helpers.on_active(9000, function(summon, ticks_since_active)
      if helpers.pending(summon, "spores") then
        spores_seen = true
      end
      if not killed and summon.active_seconds >= 120 then
        local boss = helpers.tracked(summon, "boss")
        assert(boss and boss.position, "the Plague Hulk position is missing from the summon snapshot")
        local hulk = helpers.find_entity(surface, boss.name, boss.position, 8)
        assert(hulk and hulk.valid, "the Plague Hulk entity is missing")
        local units = hulk.units
        local sortie_size = #units
        if sortie_size > 0 then
          for _, unit in ipairs(units) do
            if unit.valid then
              unit.die()
            end
          end
          killed = true
          killed_at = game.tick
        end
      elseif killed and killed_at and game.tick >= killed_at + 5 * 60 then
        assert(not spores_seen, "the Plague Hulk queued spores after its sortie died")
        assert(not approach_turret.disabled_by_script, "the Plague Hulk disabled a turret after its sortie died")
        return true
      end
      if ticks_since_active >= 9000 then
        error("the Plague Hulk sortie did not die before it approached: " .. helpers.describe_summon(summon))
      end
    end)
  end)

  test("the Colossus chooses and stores one of six variants when its beacon is lit", function()
    local valid = { "fire", "storm", "armored", "mother", "fire-spitter", "acid-spitter" }
    helpers.reset()
    storage.colossus_next.player = nil
    storage.next_colossus_variant = nil
    helpers.light("colossus", { 0, 0 })
    local summon = helpers.active()
    local state = summon and summon.boss_state
    assert(state and state.variant and state.variant_entity == "nexus-colossus-" .. state.variant,
      "the Colossus variant was not prepared when its beacon was lit")
    local known = false
    for _, variant in ipairs(valid) do
      if variant == state.variant then
        known = true
        break
      end
    end
    assert(known, "the Colossus selected an unknown variant")
    assert(storage.colossus_next.player == state.variant, "the next Colossus variant was not stored for the force")
    remote.call("nexus-bosses", "abort_summon", true)
  end)

  test("the Colossus variant and approach side survive beacon cancellation and advance after victory", function()
    remote.call("nexus-bosses", "set_next_colossus", "armored")
    helpers.light("colossus", { 0, 0 })
    local first = helpers.active()
    assert(first and first.phase == "countdown" and first.boss_state, "the first Colossus summon did not start")
    local first_variant = first.boss_state.variant
    local first_angle = first.angle
    remote.call("nexus-bosses", "abort_summon", false)

    helpers.light("colossus", { 0, 0 })
    local second = helpers.active()
    assert(second and second.boss_state, "the replacement Colossus summon did not start")
    assert(second.boss_state.variant == first_variant, "cancelling the beacon changed the next Colossus variant")
    assert(second.angle == first_angle, "cancelling the beacon changed the Colossus approach side")

    local elapsed = 0
    local defeated = false
    async(1800)
    on_tick(function()
      elapsed = elapsed + 1
      local summon = helpers.active()
      if summon and summon.phase == "active" and not defeated then
        local boss = helpers.tracked(summon, "boss")
        assert(boss and boss.position, "the Colossus boss record is missing")
        local entity = helpers.find_entity(helpers.nexus(), boss.name, boss.position, 12)
        assert(entity and entity.valid, "the Colossus entity is missing")
        remote.call("nexus-bosses", "set_next_colossus", "fire")
        assert(remote.call("nexus-bosses", "set_tracked_health", boss.unit_number, 1),
          "the Colossus health could not be changed")
        defeated = true
        entity.die()
      elseif defeated and not summon then
        assert(storage.colossus_next.player == "fire", "a victory did not choose a new Colossus variant")
        assert(storage.progress.player.colossus_variants.armored == true,
          "the Colossus victory was not recorded by variant")
        done()
        return false
      end
      if elapsed >= 1800 then
        error("the Colossus did not complete its victory transition")
      end
    end)
  end)

  test("each Colossus variant strikes without an error", function()
    local variants = { "fire", "storm", "fire-spitter", "acid-spitter" }
    local variant_index = 1
    local variant = variants[variant_index]
    local attempt_tick = game.tick
    local attack_seen = false
    local test_turrets = {}
    local spitter_group = {}
    local target_checked = false

    local function ignite()
      helpers.reset()
      variant = variants[variant_index]
      remote.call("nexus-bosses", "set_next_colossus", variant)
      helpers.light("colossus", { 0, 0 })
      attempt_tick = game.tick
      attack_seen = false
      test_turrets = {}
      spitter_group = {}
      target_checked = false
    end

    ignite()
    helpers.on_active(#variants * 2400, function(summon, _ticks_since_active)
      local state = summon.boss_state
      if state.variant == variant then
        if (variant == "fire-spitter" or variant == "acid-spitter") and #test_turrets == 0 then
          local boss = helpers.tracked(summon, "boss")
          assert(boss and boss.position, "the Colossus position is missing from the summon snapshot")
          local surface = helpers.nexus()
          local boss_entity = helpers.find_entity(surface, state.variant_entity)
          assert(boss_entity, "the Colossus entity is missing")
          local single = player_entity_at(surface, "gun-turret",
            { x = boss.position.x + 7, y = boss.position.y }, 5)
          single.destructible = false
          test_turrets[#test_turrets + 1] = single
          for _, offset in ipairs({ { 24, -3 }, { 28, 0 }, { 24, 3 } }) do
            local turret = player_entity_at(surface, "gun-turret", {
              x = boss.position.x + offset[1],
              y = boss.position.y + offset[2],
            }, 2)
            turret.destructible = false
            test_turrets[#test_turrets + 1] = turret
            spitter_group[#spitter_group + 1] = turret
          end
          boss_entity.disabled_by_script = true
        end

        local kind = "colossus-" .. variant
        local pending = helpers.pending(summon, kind)
        if pending then
          attack_seen = true
          if (variant == "fire-spitter" or variant == "acid-spitter") and not target_checked then
            local pending_data = remote.call("nexus-bosses", "get_pending_data")
            ---@cast pending_data {kind: string, at: integer, data: {position: MapPosition}}[]
            local target
            for _, entry in ipairs(pending_data) do
              if entry.kind == kind and entry.at == pending.at then
                target = entry.data.position
                break
              end
            end
            if not target then
              error("the Colossus spitter attack had no target position")
            end
            local target_in_group = false
            for _, turret in ipairs(spitter_group) do
              if util.distance(target, turret.position) <= 0.1 then
                target_in_group = true
                break
              end
            end
            assert(target_in_group, "the Colossus spitter did not target the denser group of three turrets")
            target_checked = true
          end
        elseif attack_seen then
          for _, turret in ipairs(test_turrets) do
            if turret.valid then
              turret.destroy()
            end
          end
          remote.call("nexus-bosses", "abort_summon", true)
          variant_index = variant_index + 1
          if variant_index > #variants then
            return true
          end
          ignite()
        end
      end

      if game.tick - attempt_tick >= 2400 then
        error("the Colossus " .. variant .. " attack did not complete in time: "
          .. helpers.describe_summon(summon))
      end
    end)
  end)

  test("the Armoured Colossus shell absorbs damage and breaks under weak-type damage", function()
    remote.call("nexus-bosses", "set_next_colossus", "armored")
    helpers.light("colossus", { 0, 0 })
    helpers.on_active(3600, function(summon, ticks_since_active)
      local state = summon.boss_state
      if state.shield then
        local boss = helpers.tracked(summon, "boss")
        assert(boss, "the Armoured Colossus is missing from the summon snapshot")
        local boss_entity = helpers.find_entity(helpers.nexus(), state.variant_entity, boss.position, 12)
        assert(boss_entity and boss_entity.valid, "the Armoured Colossus entity is missing")
        assert(math.abs(state.shield.limit - 0.05 * boss_entity.max_health) <= 1,
          "the shell limit is not 5 % of maximum health")
        local resist = remote.call("nexus-bosses", "resist", state.variant_entity)
        assert(resist and #resist.weak > 0, "the Armoured Colossus has no weak damage type")
        local weak_type = resist.weak[1]
        local nonweak_type
        for _, damage_type in ipairs({ "physical", "impact", "fire", "acid", "poison", "explosion", "laser", "electric" }) do
          local is_weak = false
          for _, weak in ipairs(resist.weak) do
            if weak == damage_type then
              is_weak = true
              break
            end
          end
          if not is_weak then
            nonweak_type = damage_type
            break
          end
        end
        if not nonweak_type then
          error("the Armoured Colossus has no non-weak damage type")
        end

        local health_before = boss_entity.health
        assert(health_before, "the Armoured Colossus has no current health")
        boss_entity.damage(10000, "player", nonweak_type)
        local after_nonweak = boss_entity.health
        assert(after_nonweak and math.abs(after_nonweak - health_before) <= 1,
          "non-weak damage reduced the Armoured Colossus health during its shell")

        local resistance_entry = boss_entity.prototype.resistances and boss_entity.prototype.resistances[weak_type]
        local share = resistance_entry and resistance_entry.percent or 0
        local decrease = resistance_entry and resistance_entry.decrease or 0
        local amount = (state.shield.limit + decrease) / (1 - share) + 1
        boss_entity.damage(amount, "player", weak_type)
        local after_weak = helpers.active()
        assert(after_weak and not after_weak.boss_state.shield,
          "5 % maximum-health damage of a weak type did not break the shell")
        local health_after_weak = boss_entity.health
        assert(health_after_weak and math.abs(health_after_weak - health_before) <= 1,
          "weak damage that broke the shell was not absorbed")

        boss_entity.damage(10000, "player", nonweak_type)
        local health_after_shell = boss_entity.health
        assert(health_after_shell and health_after_shell < health_after_weak - 1,
          "damage did not reduce health after the shell broke")
        remote.call("nexus-bosses", "abort_summon", true)
        return true
      end
      if ticks_since_active >= 3600 then
        error("the Armoured Colossus shield test timed out")
      end
    end)
  end)

  test("the Mother Colossus stops at 18 living escorts after four broods", function()
    helpers.reset()
    remote.call("nexus-bosses", "set_next_colossus", "mother")
    helpers.light("colossus", { 0, 0 })
    helpers.defend()
    helpers.on_active(90 * 60, function(summon, ticks_since_active)
      if ticks_since_active >= 85 * 60 then
        assert(helpers.role_count(summon, "escort") == 18,
          "the Mother Colossus should stop at 18 living escorts after four broods")
        assert(not helpers.pending(summon, "colossus-mother"),
          "the Mother Colossus queued another brood after reaching the escort cap")
        remote.call("nexus-bosses", "abort_summon", true)
        return true
      end
    end)
  end)

  test("the Colossus escalation advances at health thresholds and does not reverse after healing", function()
    helpers.light("colossus", { 0, 0 })
    local lowered = false
    local healed = false
    local lowered_again = false
    helpers.on_active(900, function(summon)
      local boss = helpers.tracked(summon, "boss")
      assert(boss and boss.initial, "the Colossus is missing from the summon snapshot")
      if not lowered then
        assert(remote.call("nexus-bosses", "set_tracked_health", boss.unit_number, boss.initial * 0.5),
          "the Colossus health could not be lowered to 50 %")
        lowered = true
      elseif not healed and summon.phase_index == 1 then
        assert(remote.call("nexus-bosses", "set_tracked_health", boss.unit_number, boss.initial * 0.9),
          "the Colossus health could not be restored to 90 %")
        healed = true
      elseif healed and not lowered_again then
        assert(summon.phase_index == 1, "healing the Colossus reversed its escalation phase")
        assert(remote.call("nexus-bosses", "set_tracked_health", boss.unit_number, boss.initial * 0.2),
          "the Colossus health could not be lowered to 20 %")
        lowered_again = true
      elseif lowered_again and summon.phase_index == 2 then
        helpers.reset()
        return true
      end
    end)
  end)

  test("the Last Commander drops six escorts", function()
    helpers.light("last-commander", { 0, 0 })
    helpers.on_active(60 * 60, function(summon, ticks_since_active)
      if summon.active_seconds >= 50 then
        assert(helpers.role_count(summon, "escort") == 6,
          "the Last Commander should have six tracked escorts after 50 seconds")
        remote.call("nexus-bosses", "abort_summon", true)
        return true
      end
      if ticks_since_active >= 3500 then
        error("the Last Commander test timed out: " .. helpers.describe_summon(summon))
      end
    end)
  end)

  test("the Last Commander marks buildings in phase two and drops beyond the beacon in phase three", function()
    local surface = helpers.nexus()
    helpers.light("last-commander", { 0, 0 })
    helpers.defend()
    local target
    local phase_one_at
    local mark_checked = false
    local function commander_timeout(summon, boss)
      local distance = target and target.valid and util.distance(boss.position, target.position) or -1
      return string.format("active_seconds=%s phase_index=%s boss_state.next_mark=%s boss_wall_distance=%s %s",
        tostring(summon.active_seconds), tostring(summon.phase_index),
        tostring(summon.boss_state and summon.boss_state.next_mark), tostring(distance),
        helpers.describe_summon(summon))
    end
    helpers.on_active(110 * 60, function(summon, ticks_since_active)
      local boss = helpers.tracked(summon, "boss")
      assert(boss and boss.position and boss.initial, "the Last Commander is missing from the summon snapshot")
      if not target then
        target = wall_at(surface, { x = boss.position.x + 40, y = boss.position.y })
        target.destructible = false
        assert(remote.call("nexus-bosses", "set_tracked_health", boss.unit_number, boss.initial * 0.5),
          "the Commander health could not be lowered to phase two")
      elseif summon.phase_index == 1 and not mark_checked then
        phase_one_at = phase_one_at or game.tick
        if target and target.valid then
          local nearby = surface.find_non_colliding_position("stone-wall",
            { x = boss.position.x + 15, y = boss.position.y }, 8, 1)
          assert(nearby and target.teleport(nearby), "the Commander test wall could not stay near the boss")
        end
        local mark = helpers.pending(summon, "strike")
        if mark then
          local found_target = false
          local pending_data = remote.call("nexus-bosses", "get_pending_data")
          ---@cast pending_data {kind: string, at: integer, data: table}[]
          for _, entry in ipairs(pending_data) do
            if entry.kind == "strike" and entry.at == mark.at and entry.data.target == target.unit_number then
              found_target = true
              break
            end
          end
          assert(found_target, "the Commander strike did not retain its marked building")
          assert(game.tick - phase_one_at <= (12 / summon.effective_frequency + 5) * 60,
            "the Commander did not queue its phase-two strike within its scaled interval and warning")
          mark_checked = true
          assert(remote.call("nexus-bosses", "set_tracked_health", boss.unit_number, boss.initial * 0.2),
            "the Commander health could not be lowered to phase three")
        elseif game.tick - phase_one_at > (12 / summon.effective_frequency + 5) * 60 then
          error("the Commander did not queue a phase-two strike: " .. commander_timeout(summon, boss))
        end
      elseif mark_checked and summon.phase_index == 2 then
        local drop = helpers.pending(summon, "drop")
        if drop then
          ---@type MapPosition|nil
          local drop_position
          local pending_data = remote.call("nexus-bosses", "get_pending_data")
          ---@cast pending_data {kind: string, at: integer, data: {position: MapPosition}}[]
          for _, entry in ipairs(pending_data) do
            if entry.kind == "drop" and entry.at == drop.at then
              drop_position = entry.data.position
              break
            end
          end
          if not drop_position then
            error("the phase-three drop has no position")
          end
          local beacon_position = summon.beacon_position --[[@as MapPosition]]
          assert(util.distance(drop_position, boss.position) > util.distance(beacon_position, boss.position),
            "the phase-three drop did not land beyond the beacon on the side away from the Commander")
          helpers.reset()
          return true
        end
      end
      if ticks_since_active >= 6000 then
        error("the Last Commander phase test timed out: " .. commander_timeout(summon, boss))
      end
    end)
  end)

  test("the Last Commander queues a nuke when its setting is enabled", function()
    local setting_name = "nexus-bosses-commander-nuke"
    local setting = settings.global[setting_name]
    local original = setting and setting.value
    local restored = false
    local function restore_setting()
      if not restored then
        ---@diagnostic disable-next-line: assign-type-mismatch
        -- luacheck: ignore 122
        settings.global[setting_name] = { value = original }
        restored = true
      end
    end
    after_test(restore_setting)
    local function timeout_details(summon)
      return string.format("active_seconds=%s effective_frequency=%s boss_state.next_nuke=%s",
        tostring(summon.active_seconds), tostring(summon.effective_frequency),
        tostring(summon.boss_state and summon.boss_state.next_nuke))
    end

    local ok, message = pcall(function()
      ---@diagnostic disable-next-line: assign-type-mismatch
      -- luacheck: ignore 122
      settings.global[setting_name] = { value = true }
      helpers.light("last-commander", { 0, 0 })
      helpers.defend()
      helpers.on_active(110 * 60, function(summon, ticks_since_active)
        local callback_ok, complete = pcall(function()
          if helpers.pending(summon, "nuke") then
            return true
          end
          if summon.active_seconds > math.ceil(90 / summon.effective_frequency) + 2 then
            error("the Commander did not queue a nuke while its setting was enabled: "
              .. timeout_details(summon))
          end
          if ticks_since_active >= 110 * 60 then
            error("the Commander nuke setting test timed out: " .. timeout_details(summon))
          end
          return false
        end)
        if not callback_ok then
          restore_setting()
          helpers.reset()
          error(complete)
        end
        if complete then
          restore_setting()
          helpers.reset()
        end
        return complete
      end)
    end)
    if not ok then
      restore_setting()
      helpers.reset()
      error(message)
    end
  end)

  test("the Last Commander does not queue a nuke when its setting is disabled", function()
    local setting_name = "nexus-bosses-commander-nuke"
    local setting = settings.global[setting_name]
    local original = setting and setting.value
    local restored = false
    local function restore_setting()
      if not restored then
        ---@diagnostic disable-next-line: assign-type-mismatch
        -- luacheck: ignore 122
        settings.global[setting_name] = { value = original }
        restored = true
      end
    end
    after_test(restore_setting)

    local ok, message = pcall(function()
      ---@diagnostic disable-next-line: assign-type-mismatch
      -- luacheck: ignore 122
      settings.global[setting_name] = { value = false }
      helpers.light("last-commander", { 0, 0 })
      helpers.defend()
      helpers.on_active(110 * 60, function(summon, ticks_since_active)
        local callback_ok, complete = pcall(function()
          if helpers.pending(summon, "nuke") then
            error("the Commander queued a nuke while its setting was disabled")
          end
          if summon.active_seconds > math.ceil(90 / summon.effective_frequency) + 2 then
            return true
          end
          if ticks_since_active >= 110 * 60 then
            error("the Commander nuke setting test timed out")
          end
          return false
        end)
        if not callback_ok then
          restore_setting()
          helpers.reset()
          error(complete)
        end
        if complete then
          restore_setting()
          helpers.reset()
        end
        return complete
      end)
    end)
    if not ok then
      restore_setting()
      helpers.reset()
      error(message)
    end
  end)

  test("the Storm Guardian calls its own storm after 60 seconds without a Nexus-Threat storm", function()
    helpers.light("storm-guardian", { 0, 0 })
    helpers.defend()
    local damaged = false
    local damaged_health
    helpers.on_active(90 * 60, function(summon)
      local boss = helpers.tracked(summon, "boss")
      assert(boss and boss.initial, "the Storm Guardian is missing from the summon snapshot")
      if not damaged and summon.active_seconds >= 5 then
        damaged_health = boss.initial * 0.5
        assert(remote.call("nexus-bosses", "set_tracked_health", boss.unit_number, damaged_health),
          "the Storm Guardian health could not be lowered for the healing check")
        damaged = true
      elseif summon.active_seconds >= 65 then
        assert(summon.boss_state and summon.boss_state.own_storm,
          "the Storm Guardian did not report its own storm after 60 seconds")
        local current_health = boss.health
        if type(current_health) ~= "number" or type(damaged_health) ~= "number"
          or current_health <= damaged_health + 1 then
          error("the Storm Guardian did not heal during its own storm")
        end
        helpers.reset()
        return true
      end
    end)
  end)

  test("the Twin Maws heal while both live", function()
    helpers.nexus()
    helpers.light("twin-maws", { 0, 0 })
    local damaged_name
    ---@type number
    local damaged_health = 0
    local damaged_at
    helpers.on_active(700, function(summon, ticks_since_active)
      if not damaged_at then
        local maw = helpers.tracked(summon, "boss", "nexus-maw-fire")
        assert(maw and maw.health, "the fire maw is missing from the summon snapshot")
        damaged_name = maw.name
        damaged_health = maw.health - 10000
        assert(remote.call("nexus-bosses", "set_tracked_health", maw.unit_number, damaged_health),
          "the fire maw health could not be lowered")
        damaged_at = game.tick
      elseif game.tick >= damaged_at + 2 * 60 then
        local maw = helpers.tracked(summon, "boss", damaged_name)
        assert(maw and maw.health and maw.health > damaged_health + 1,
          "the Twin Maws did not heal the damaged maw while both were alive")
        remote.call("nexus-bosses", "abort_summon", true)
        return true
      end
      if ticks_since_active >= 700 then
        error("the Twin Maws mutual healing test timed out")
      end
    end)
  end)

  test("a dead Twin Maw rises after 20 seconds with half health", function()
    local surface = helpers.nexus()
    helpers.light("twin-maws", { 0, 0 })
    local death_tick = 0
    local fallen_name = ""
    ---@type MapPosition.struct
    local fallen_position = { x = 0, y = 0 }
    ---@type number
    local max_health = 0
    local death_after_active_ticks
    helpers.on_active(1800, function(summon, ticks_since_active)
      if death_tick == 0 then
        local maw = helpers.tracked(summon, "boss", "nexus-maw-fire")
        assert(maw and maw.position, "the fire maw is missing from the summon snapshot")
        local entity = helpers.find_entity(surface, maw.name, maw.position, 2)
        assert(entity, "the fire maw entity is missing")
        fallen_name = maw.name
        local x, y = util.xy(entity.position)
        fallen_position = { x = x, y = y }
        max_health = entity.max_health
        death_tick = game.tick
        death_after_active_ticks = ticks_since_active
        entity.die()
      end
      if death_tick > 0 and death_after_active_ticks and ticks_since_active >= death_after_active_ticks + 20 * 60 then
        local revived = helpers.tracked(summon, "boss", fallen_name)
        local entity = helpers.find_entity(surface, fallen_name, fallen_position, 1)
        if entity then
          assert(revived and not revived.dead,
            "the dead Twin Maw did not return as a living tracked entity")
          local health = assert(entity.health, "the risen fire maw has no health")
          assert(health >= max_health / 2 - 1 and health <= max_health / 2 + max_health * 0.003 + 1,
            "the risen Twin Maw should have half of its maximum health, with at most one mutual heal"
              .. string.format(": health=%.3f max=%.3f tick_after_death=%d", health, max_health,
                game.tick - death_tick))
          local x, y = util.xy(entity.position)
          assert(math.abs(x - fallen_position.x) < 0.1 and math.abs(y - fallen_position.y) < 0.1,
            "the Twin Maw did not rise at its original position")
          remote.call("nexus-bosses", "abort_summon", true)
          return true
        end
        if death_after_active_ticks and ticks_since_active >= death_after_active_ticks + 23 * 60 then
          error("the Twin Maw did not rise within 23 seconds of death")
        end
      end
      if ticks_since_active >= 1800 then
        error("the Twin Maw rise test timed out")
      end
    end)
  end)

  test("killing both Twin Maws within five seconds wins the trial", function()
    local surface = helpers.nexus()
    helpers.light("twin-maws", { 0, 0 })
    local first_kill_tick = 0
    local killed_both = false
    local elapsed = 0
    async(900)
    on_tick(function()
      elapsed = elapsed + 1
      local summon = helpers.active()
      if summon and summon.phase == "active" and first_kill_tick == 0 then
        local first = helpers.tracked(summon, "boss", "nexus-maw-fire")
        local entity = first and helpers.find_entity(surface, first.name, first.position, 2)
        assert(entity, "the fire maw entity is missing")
        first_kill_tick = game.tick
        entity.die()
      elseif summon and first_kill_tick > 0 and not killed_both then
        assert(game.tick - first_kill_tick <= 5 * 60, "the second maw was not killed within five seconds")
        local second = helpers.tracked(summon, "boss", "nexus-maw-acid")
        local entity = second and helpers.find_entity(surface, second.name, second.position, 2)
        assert(entity, "the acid maw entity is missing")
        entity.die()
        killed_both = true
      elseif killed_both and not summon then
        local state = remote.call("nexus-bosses", "get_state") --[[@as {defeated: table<string, table<string, boolean>>}|nil]]
        assert(state and state.defeated.player["twin-maws"] == true,
          "defeating both Twin Maws did not record a victory")
        done()
        return false
      end
      if elapsed >= 900 then
        error("the Twin Maws victory test timed out")
      end
    end)
  end)

  test("all nine boss beacons spawn their own boss without a BM summon state", function()
    local bosses = {
      "arachnid-queen", "watcher", "rogue-spidertron", "twin-maws", "colossus", "plague-hulk",
      "storm-guardian", "devourer", "last-commander",
    }
    local index = 1
    local attempt_tick = game.tick
    local handled_id

    local function ignite()
      helpers.reset()
      local boss_id = assert(bosses[index], "the boss sequence ended unexpectedly")
      helpers.light(boss_id, { 0, 0 })
      attempt_tick = game.tick
    end

    ignite()
    helpers.on_active(#bosses * 13 * 60, function(summon, _ticks_since_active)
      if summon.id ~= handled_id then
        handled_id = summon.id
        index = index + 1
        if index > #bosses then
          remote.call("nexus-bosses", "abort_summon", true)
          return true
        end
        ignite()
      end
      if game.tick - attempt_tick >= 13 * 60 then
        local boss_id = assert(bosses[index], "the boss sequence ended unexpectedly")
        error("the " .. boss_id .. " beacon did not become active in time: " .. helpers.describe_summon(summon))
      end
    end)
  end)
end)
