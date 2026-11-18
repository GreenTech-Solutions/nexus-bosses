-- Tests for the Watcher and Rogue Spidertron using headless summon snapshots.

local helpers = require("tests.helpers")

---@param summon table
---@param role string
---@return table|nil
local function tracked(summon, role)
  for _, record in ipairs(summon.tracked or {}) do
    if record.required and record.role == role then
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
---@return LuaEntity|nil
local function find_valid_entity(surface, name)
  for _, entity in ipairs(surface.find_entities_filtered({ name = name })) do
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
              local drone = game.get_entity_by_unit_number(record.unit_number)
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
        local entity = game.get_entity_by_unit_number(boss.unit_number)
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
end)
