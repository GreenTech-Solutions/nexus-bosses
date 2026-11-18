-- Tests for boss mechanics using headless summon snapshots.

local helpers = require("tests.helpers")
local util = require("scripts.nb_util")

---@param summon table
---@param role string
---@param name string|nil
---@return table|nil
local function tracked(summon, role, name)
  for _, record in ipairs(summon.tracked or {}) do
    if record.required and record.role == role and (not name or record.name == name) then
      return record
    end
  end
end

---@param summon table
---@param kind string
---@return table|nil
local function pending(summon, kind)
  for _, entry in ipairs(summon.pending or {}) do
    if entry.kind == kind then
      return entry
    end
  end
end

---@param summon table
---@param role string
---@return integer
local function role_count(summon, role)
  local count = 0
  for _, record in ipairs(summon.tracked or {}) do
    if record.role == role and not record.dead and not record.gone then
      count = count + 1
    end
  end
  return count
end

---@param surface LuaSurface
---@param name string
---@param position MapPosition|nil
---@param radius number|nil
---@return LuaEntity|nil
local function find_valid_entity(surface, name, position, radius)
  local filters = { name = name }
  if position then
    filters.position = position
    filters.radius = radius or 5
  end
  for _, entity in ipairs(surface.find_entities_filtered(filters)) do
    if entity.valid then
      return entity
    end
  end
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

describe("reworked bosses", function()
  before_each(function()
    helpers.reset()
    helpers.nexus()
  end)

  test("the Watcher queues a strike against a nearby player building", function()
    local surface = helpers.nexus()
    helpers.light("watcher", { 0, 0 })
    local active_at
    local elapsed = 0
    local wall
    local last_summon
    async(1400)
    on_tick(function()
      elapsed = elapsed + 1
      local summon = helpers.active()
      last_summon = summon
      if summon and summon.phase == "active" and not wall then
        active_at = game.tick
        local boss = tracked(summon, "boss")
        assert(boss and boss.position, "the Watcher position is missing from the summon snapshot")
        assert(role_count(summon, "boss") == 1 and role_count(summon, "escort") == 6,
          "the Watcher should appear with one boss and six escort drones")
        wall = wall_at(surface, { x = boss.position.x + 20, y = boss.position.y })
      end
      if wall and active_at and game.tick >= active_at + 13 * 60 then
        local current = helpers.active()
        if current and pending(current, "strike") then
          done()
          return false
        end
      end
      if elapsed >= 1400 then
        if active_at then
          error("the Watcher did not queue a strike in time: " .. helpers.describe_summon(last_summon))
        end
        error("the Watcher did not become active within the test window: " .. helpers.describe_summon(last_summon))
      end
    end)
  end)

  test("the Watcher cancels a queued strike when its drones die", function()
    local surface = helpers.nexus()
    helpers.light("watcher", { 0, 0 })
    local wall
    local wall_health
    local strike_at
    local elapsed = 0
    async(1400)
    on_tick(function()
      elapsed = elapsed + 1
      local summon = helpers.active()
      if summon and summon.phase == "active" and not wall then
        local boss = tracked(summon, "boss")
        assert(boss and boss.position, "the Watcher position is missing from the summon snapshot")
        assert(role_count(summon, "boss") == 1 and role_count(summon, "escort") == 6,
          "the Watcher should appear with one boss and six escort drones")
        wall = wall_at(surface, { x = boss.position.x + 20, y = boss.position.y })
        wall_health = wall.health
      elseif wall and not strike_at then
        local strike = summon and pending(summon, "strike")
        if strike then
          strike_at = strike.at
          ---@cast summon table
          for _, record in ipairs(summon.tracked) do
            if record.role == "escort" and not record.dead and not record.gone then
              local drone = find_valid_entity(surface, record.name, record.position, 1)
              if drone and drone.valid then
                drone.die()
              end
            end
          end
        end
      elseif strike_at and game.tick >= strike_at + 20 then
        ---@cast wall LuaEntity
        assert(wall.valid and wall.health == wall_health,
          "the Watcher fired its queued strike after all drones had died")
        done()
        return false
      end
      if elapsed >= 1400 then
        error("the Watcher strike cancellation test timed out")
      end
    end)
  end)

  test("the Rogue Spidertron's EMP disables and restores nearby player buildings", function()
    local surface = helpers.nexus()
    helpers.light("rogue-spidertron", { 0, 0 })
    local machine
    local disabled_at
    local elapsed = 0
    async(1900)
    on_tick(function()
      elapsed = elapsed + 1
      local summon = helpers.active()
      if summon and summon.phase == "active" and not machine then
        local boss = tracked(summon, "boss")
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
        local entity = find_valid_entity(surface, boss.name, boss.position, 5)
        assert(entity and entity.valid and entity.teleport({ x = boss.position.x + 1, y = boss.position.y }),
          "the Rogue Spidertron could not be moved into EMP range")
      elseif machine and not disabled_at and machine.valid and machine.disabled_by_script then
        disabled_at = game.tick
        assert(disabled_at <= game.tick, "the EMP did not disable the test machine")
      elseif disabled_at and game.tick >= disabled_at + 960 then
        ---@cast machine LuaEntity
        assert(machine.valid and not machine.disabled_by_script, "the EMP did not restore the test machine")
        done()
        return false
      end
      if elapsed >= 1900 then
        error("the Rogue Spidertron EMP test timed out")
      end
    end)
  end)

  test("the Colossus chooses one of six variants when its beacon is lit", function()
    local valid = { "fire", "storm", "armored", "mother", "fire-spitter", "acid-spitter" }
    local seen = {}
    local run = 0
    local elapsed = 0
    local attempt_tick = game.tick
    local function ignite()
      helpers.reset()
      helpers.light("colossus", { 0, 0 })
      run = run + 1
      attempt_tick = game.tick
    end

    ignite()
    async(30 * 600)
    on_tick(function()
      elapsed = elapsed + 1
      local summon = helpers.active()
      if summon then
        local known = false
        for _, variant in ipairs(valid) do
          if variant == summon.variant then
            known = true
            break
          end
        end
        assert(known, "the Colossus selected an unknown variant")
        assert(summon.variant_entity == "nexus-colossus-" .. summon.variant,
          "the Colossus snapshot has the wrong entity name")
        if summon.phase == "active" then
          seen[summon.variant] = true
          remote.call("nexus-bosses", "abort_summon", true)
          if run == 30 then
            local count = 0
            for _ in pairs(seen) do
              count = count + 1
            end
            assert(count > 1, "the random Colossus selection produced only one variant in 30 fights")
            done()
            return false
          end
          ignite()
        elseif game.tick - attempt_tick >= 600 then
          error("the Colossus did not appear within the test window: " .. helpers.describe_summon(summon))
        end
      elseif game.tick - attempt_tick >= 600 then
        error("the Colossus summon disappeared before appearing")
      end
      if elapsed >= 30 * 600 then
        error("the Colossus variant selection test timed out")
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
    local elapsed = 0
    local last_summon

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
    async(#variants * 2400)
    on_tick(function()
      elapsed = elapsed + 1
      local summon = helpers.active()
      last_summon = summon
      if summon and summon.phase == "active" and summon.variant == variant then
        if (variant == "fire-spitter" or variant == "acid-spitter") and not test_turret then
          local boss = tracked(summon, "boss")
          assert(boss and boss.position, "the Colossus position is missing from the summon snapshot")
          local surface = helpers.nexus()
          local boss_entity = find_valid_entity(surface, summon.variant_entity)
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
        if pending(summon, kind) then
          attack_seen = true
        elseif attack_seen then
          if test_turret and test_turret.valid then
            test_turret.destroy()
          end
          remote.call("nexus-bosses", "abort_summon", true)
          variant_index = variant_index + 1
          if variant_index > #variants then
            done()
            return false
          end
          ignite()
        end
      end

      if game.tick - attempt_tick >= 2400 then
        error("the Colossus " .. variant .. " attack did not complete in time: "
          .. helpers.describe_summon(last_summon))
      end
      if elapsed >= #variants * 2400 then
        error("the Colossus strike test timed out for " .. variant .. ": "
          .. helpers.describe_summon(last_summon))
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
    local elapsed = 0
    async(3600)
    on_tick(function()
      elapsed = elapsed + 1
      local summon = helpers.active()
      if summon and summon.phase == "active" and summon.shield and not damaged_at then
        local boss = tracked(summon, "boss")
        assert(boss, "the Armoured Colossus is missing from the summon snapshot")
        shield_health = summon.shield.health
        boss_entity = find_valid_entity(helpers.nexus(), summon.variant_entity)
        assert(boss_entity and boss_entity.valid, "the Armoured Colossus entity is missing")
        boss_entity.damage(100000, "enemy", "physical")
        damaged_at = game.tick
      elseif damaged_at and game.tick >= damaged_at + 60 then
        ---@cast boss_entity LuaEntity
        assert(boss_entity.valid and boss_entity.health >= shield_health,
          "the Armoured Colossus did not restore its shield health")
        remote.call("nexus-bosses", "abort_summon", true)
        done()
        return false
      end
      if elapsed >= 3600 then
        error("the Armoured Colossus shield test timed out")
      end
    end)
  end)

  test("the Mother Colossus summons six tracked escorts after 24 seconds", function()
    helpers.reset()
    remote.call("nexus-bosses", "set_next_colossus", "mother")
    helpers.light("colossus", { 0, 0 })
    local active_at
    local elapsed = 0
    async(2400)
    on_tick(function()
      elapsed = elapsed + 1
      local summon = helpers.active()
      if summon and summon.phase == "active" then
        active_at = active_at or game.tick
        if game.tick >= active_at + 24 * 60 then
          assert(role_count(summon, "escort") == 6,
            "the Mother Colossus should have six tracked escorts after its brood attack")
          remote.call("nexus-bosses", "abort_summon", true)
          done()
          return false
        end
      end
      if elapsed >= 2400 then
        error("the Mother Colossus brood test timed out")
      end
    end)
  end)

  test("the Last Commander drops six escorts and skips atomic rockets when BM nukes are disabled", function()
    local setting = settings.global["bm-allow-nuker"]
    assert(setting and setting.value == false, "set bm-allow-nuker=false for the Last Commander test")
    helpers.light("last-commander", { 0, 0 })
    local checked_drop = false
    local elapsed = 0
    local last_summon
    async(7000)
    on_tick(function()
      elapsed = elapsed + 1
      local summon = helpers.active()
      last_summon = summon
      if summon and summon.phase == "active" then
        assert(not pending(summon, "nuke"), "the Last Commander queued an atomic rocket with bm-allow-nuker off")
        if summon.active_seconds >= 50 and not checked_drop then
          assert(role_count(summon, "escort") == 6,
            "the Last Commander should have six tracked escorts after 50 seconds")
          checked_drop = true
        end
        if summon.active_seconds >= 100 then
          assert(checked_drop, "the Last Commander did not deploy its first escort drop")
          remote.call("nexus-bosses", "abort_summon", true)
          done()
          return false
        end
      end
      if elapsed >= 7000 then
        error("the Last Commander test timed out: " .. helpers.describe_summon(last_summon))
      end
    end)
  end)

  test("the Twin Maws heal while both live", function()
    helpers.nexus()
    helpers.light("twin-maws", { 0, 0 })
    local damaged_name
    local damaged_health
    local damaged_at
    local elapsed = 0
    async(700)
    on_tick(function()
      elapsed = elapsed + 1
      local summon = helpers.active()
      if summon and summon.phase == "active" and not damaged_at then
        local maw = tracked(summon, "boss", "nexus-maw-fire")
        assert(maw and maw.health, "the fire maw is missing from the summon snapshot")
        damaged_name = maw.name
        damaged_health = maw.health - 10000
        assert(remote.call("nexus-bosses", "set_tracked_health", maw.unit_number, damaged_health),
          "the fire maw health could not be lowered")
        damaged_at = game.tick
      elseif damaged_at and game.tick >= damaged_at + 2 * 60 then
        local current = helpers.active()
        local maw = current and tracked(current, "boss", damaged_name)
        assert(maw and maw.health and maw.health > damaged_health,
          "the Twin Maws did not heal the damaged maw while both were alive")
        remote.call("nexus-bosses", "abort_summon", true)
        done()
        return false
      end
      if elapsed >= 700 then
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
    local elapsed = 0
    async(1800)
    on_tick(function()
      elapsed = elapsed + 1
      local summon = helpers.active()
      if summon and summon.phase == "active" and death_tick == 0 then
        local maw = tracked(summon, "boss", "nexus-maw-fire")
        assert(maw and maw.position, "the fire maw is missing from the summon snapshot")
        local entity = find_valid_entity(surface, maw.name, maw.position, 2)
        assert(entity, "the fire maw entity is missing")
        fallen_name = maw.name
        local x, y = util.xy(entity.position)
        fallen_position = { x = x, y = y }
        max_health = entity.max_health
        death_tick = game.tick
        entity.die()
      end
      if death_tick > 0 and game.tick >= death_tick + 20 * 60 then
        local current = helpers.active()
        local revived = current and tracked(current, "boss", fallen_name)
        local entity = find_valid_entity(surface, fallen_name, fallen_position, 1)
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
          done()
          return false
        end
        if game.tick >= death_tick + 23 * 60 then
          error("the Twin Maw did not rise within 23 seconds of death")
        end
      end
      if elapsed >= 1800 then
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
        local first = tracked(summon, "boss", "nexus-maw-fire")
        local entity = first and find_valid_entity(surface, first.name, first.position, 2)
        assert(entity, "the fire maw entity is missing")
        first_kill_tick = game.tick
        entity.die()
      elseif summon and first_kill_tick > 0 and not killed_both then
        assert(game.tick - first_kill_tick <= 5 * 60, "the second maw was not killed within five seconds")
        local second = tracked(summon, "boss", "nexus-maw-acid")
        local entity = second and find_valid_entity(surface, second.name, second.position, 2)
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
    local elapsed = 0
    local last_summon

    local function ignite()
      helpers.reset()
      local boss_id = assert(bosses[index], "the boss sequence ended unexpectedly")
      helpers.light(boss_id, { 0, 0 })
      attempt_tick = game.tick
    end

    ignite()
    async(#bosses * 13 * 60)
    on_tick(function()
      elapsed = elapsed + 1
      local summon = helpers.active()
      last_summon = summon
      if summon then
        assert(summon["bm"] == nil, "a boss summon still contains Big Monsters state")
        if summon.phase == "active" then
          index = index + 1
          if index > #bosses then
            remote.call("nexus-bosses", "abort_summon", true)
            done()
            return false
          end
          ignite()
        elseif game.tick - attempt_tick >= 13 * 60 then
          local boss_id = assert(bosses[index], "the boss sequence ended unexpectedly")
          error("the " .. boss_id .. " beacon did not become active in time: "
            .. helpers.describe_summon(summon))
        end
      elseif game.tick - attempt_tick >= 13 * 60 then
        local boss_id = assert(bosses[index], "the boss sequence ended unexpectedly")
        error("the " .. boss_id .. " summon disappeared before appearing")
      end
      if elapsed >= #bosses * 13 * 60 then
        error("the nine-boss spawn test timed out: " .. helpers.describe_summon(last_summon))
      end
    end)
  end)
end)
