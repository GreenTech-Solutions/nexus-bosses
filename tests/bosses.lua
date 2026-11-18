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
end)
