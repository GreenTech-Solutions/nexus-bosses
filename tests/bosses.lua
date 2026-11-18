-- Tests for boss mechanics using headless summon snapshots.

local helpers = require("tests.helpers")
local util = require("scripts.nb_util")

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

  test("the Plague Hulk's spores disable and restore a nearby player turret", function()
    local surface = helpers.nexus()
    helpers.light("plague-hulk", { 0, 0 })
    local turret
    local disabled_at
    helpers.on_active(9000, function(summon, ticks_since_active)
      if not turret then
        local boss = helpers.tracked(summon, "boss")
        assert(boss and boss.position, "the Plague Hulk position is missing from the summon snapshot")
        local position = surface.find_non_colliding_position("gun-turret", {
          x = boss.position.x + 20, y = boss.position.y,
        }, 8, 1)
        assert(position, "there was no clear spot for the Plague Hulk test turret")
        turret = surface.create_entity({ name = "gun-turret", position = position, force = "player" })
        assert(turret, "the Plague Hulk test turret could not be created")
        turret.destructible = false
      elseif turret and turret.valid and not disabled_at and turret.disabled_by_script then
        disabled_at = game.tick
      elseif disabled_at and game.tick >= disabled_at + 15 * 60 + 20 then
        ---@cast turret LuaEntity
        assert(turret.valid and not turret.disabled_by_script,
          "the Plague Hulk did not restore the turret after 15 seconds")
        return true
      end
      if ticks_since_active >= 9000 then
        error("the Plague Hulk spore test timed out: " .. helpers.describe_summon(summon))
      end
    end)
  end)

  test("the Colossus chooses one of six variants when its beacon is lit", function()
    local valid = { "fire", "storm", "armored", "mother", "fire-spitter", "acid-spitter" }
    local seen = {}
    local run = 0
    local attempt_tick = game.tick
    local function ignite()
      helpers.reset()
      helpers.light("colossus", { 0, 0 })
      run = run + 1
      attempt_tick = game.tick
      local summon = helpers.active()
      local state = summon and summon.boss_state
      assert(state and state.variant and state.variant_entity == "nexus-colossus-" .. state.variant,
        "the Colossus variant was not prepared when its beacon was lit")
    end

    ignite()
    local handled_id
    helpers.on_active(30 * 600, function(summon, _ticks_since_active)
      local state = summon.boss_state
      local known = false
      for _, variant in ipairs(valid) do
        if variant == state.variant then
          known = true
          break
        end
      end
      assert(known, "the Colossus selected an unknown variant")
      assert(state.variant_entity == "nexus-colossus-" .. state.variant,
        "the Colossus snapshot has the wrong entity name")
      if summon.id ~= handled_id then
        handled_id = summon.id
        seen[state.variant] = true
        remote.call("nexus-bosses", "abort_summon", true)
        if run == 30 then
          local count = 0
          for _ in pairs(seen) do
            count = count + 1
          end
          assert(count > 1, "the random Colossus selection produced only one variant in 30 fights")
          return true
        end
        ignite()
      end
      if game.tick - attempt_tick >= 600 then
        error("the Colossus did not appear within the test window: " .. helpers.describe_summon(summon))
      end
    end)
  end)

  test("each Colossus variant strikes without an error", function()
    local variants = { "fire", "storm", "fire-spitter", "acid-spitter" }
    local variant_index = 1
    local variant = variants[variant_index]
    local attempt_tick = game.tick
    local attack_seen = false
    local test_turret

    local function ignite()
      helpers.reset()
      variant = variants[variant_index]
      remote.call("nexus-bosses", "set_next_colossus", variant)
      helpers.light("colossus", { 0, 0 })
      attempt_tick = game.tick
      attack_seen = false
      test_turret = nil
    end

    ignite()
    helpers.on_active(#variants * 2400, function(summon, _ticks_since_active)
      local state = summon.boss_state
      if state.variant == variant then
        if (variant == "fire-spitter" or variant == "acid-spitter") and not test_turret then
          local boss = helpers.tracked(summon, "boss")
          assert(boss and boss.position, "the Colossus position is missing from the summon snapshot")
          local surface = helpers.nexus()
          local boss_entity = helpers.find_entity(surface, state.variant_entity)
          assert(boss_entity, "the Colossus entity is missing")
          local turret_position = surface.find_non_colliding_position("gun-turret", {
            x = boss.position.x + 10, y = boss.position.y,
          }, 3, 1)
          assert(turret_position, "there was no clear spot for the Colossus test turret")
          local turret = surface.create_entity({
            name = "gun-turret",
            position = turret_position,
            force = "player",
          })
          assert(turret, "the Colossus test turret could not be created")
          turret.destructible = false
          boss_entity.disabled_by_script = true
          test_turret = turret
        end

        local kind = "colossus-" .. variant
        if helpers.pending(summon, kind) then
          attack_seen = true
        elseif attack_seen then
          if test_turret and test_turret.valid then
            test_turret.destroy()
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

  test("the Armoured Colossus restores its health during its shield", function()
    helpers.reset()
    remote.call("nexus-bosses", "set_next_colossus", "armored")
    helpers.light("colossus", { 0, 0 })
    local damaged_at
    local shield_health
    local boss_entity
    helpers.on_active(3600, function(summon, ticks_since_active)
      local state = summon.boss_state
      if state.shield and not damaged_at then
        local boss = helpers.tracked(summon, "boss")
        assert(boss, "the Armoured Colossus is missing from the summon snapshot")
        shield_health = state.shield.health
        assert(shield_health, "the Armoured Colossus shield has no health")
        boss_entity = helpers.find_entity(helpers.nexus(), state.variant_entity)
        assert(boss_entity and boss_entity.valid, "the Armoured Colossus entity is missing")
        boss_entity.damage(100000, "enemy", "physical")
        damaged_at = game.tick
      elseif damaged_at and game.tick >= damaged_at + 60 then
        ---@cast boss_entity LuaEntity
        assert(boss_entity.valid, "the Armoured Colossus did not survive its shield test")
        local current_health = boss_entity.health
        assert(current_health and current_health + 1 >= shield_health,
          "the Armoured Colossus did not restore its shield health")
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
