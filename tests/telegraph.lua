-- Tests for delayed attacks using the summon snapshot and the test/debug remote functions.

local helpers = require("tests.helpers")

---@param summon table
---@return table|nil
local function boss_record(summon)
  for _, record in ipairs(summon.tracked) do
    if record.required and record.role == "boss" then
      return record
    end
  end
end

---@param summon table
---@param kind string
---@return table|nil
local function pending_entry(summon, kind)
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
  for _, record in ipairs(summon.tracked) do
    if record.role == role and not record.dead and not record.gone then
      count = count + 1
    end
  end
  return count
end

---@param a MapPosition
---@param b MapPosition
---@return number
local function distance(a, b)
  ---@cast a MapPosition.struct
  ---@cast b MapPosition.struct
  local dx = a.x - b.x
  local dy = a.y - b.y
  return math.sqrt(dx * dx + dy * dy)
end

describe("boss telegraphs", function()
  before_each(function()
    helpers.reset()
    helpers.nexus()
  end)

  test("the Queen marks nest positions before the nests appear", function()
    helpers.light("arachnid-queen", { 0, 0 })
    local health_tick
    local nests_at
    async(800)
    on_tick(function()
      local summon = helpers.active()
      if not (summon and summon.phase == "active") then
        return
      end
      if not health_tick then
        local boss = boss_record(summon)
        if boss then
          assert(remote.call("nexus-bosses", "set_tracked_health", boss.unit_number, boss.initial * 0.6),
            "the Queen health could not be changed")
          health_tick = game.tick
        end
      elseif not nests_at then
        local entry = pending_entry(summon, "nests")
        if entry then
          nests_at = entry.at
          assert(nests_at > game.tick, "the nest telegraph did not have a delay")
          assert(role_count(summon, "nest") == 0, "nests appeared before their telegraph expired")
        elseif game.tick > health_tick + 70 then
          error("the Queen did not queue the nest attack after crossing two thirds health")
        end
      elseif game.tick < nests_at then
        assert(role_count(summon, "nest") == 0, "nests appeared before their telegraph expired")
      elseif role_count(summon, "nest") > 0 then
        done()
        return false
      elseif game.tick > nests_at + 60 then
        error("the Queen nests did not appear when their telegraph expired")
      end
    end)
  end)

  test("the Devourer rises near the point marked before its dive", function()
    helpers.light("devourer", { 0, 0 })
    local health_tick
    local rise_at
    ---@type MapPosition|nil
    local target
    async(1000)
    on_tick(function()
      local summon = helpers.active()
      if not (summon and summon.phase == "active") then
        return
      end
      if not health_tick then
        local boss = boss_record(summon)
        if boss then
          assert(remote.call("nexus-bosses", "set_tracked_health", boss.unit_number, boss.initial * 0.4),
            "the Devourer health could not be changed")
          health_tick = game.tick
        end
      elseif not rise_at then
        local entry = pending_entry(summon, "rise")
        if entry then
          rise_at = entry.at
          assert(rise_at > game.tick, "the rise telegraph did not have a delay")
          local pending_data = remote.call("nexus-bosses", "get_pending_data")
          ---@cast pending_data {kind: string, at: integer, data: {position: MapPosition}}[]
          for _, detail in ipairs(pending_data) do
            if detail.kind == "rise" and detail.at == rise_at then
              target = detail.data.position
              break
            end
          end
          if not target then
            error("the saved rise position is missing")
          end
        elseif game.tick > health_tick + 70 then
          error("the Devourer did not queue its rise after crossing half health")
        end
      elseif game.tick >= rise_at then
        local boss = boss_record(summon)
        if target and boss and not boss.hidden and boss.position and boss.health > 0 then
          assert(distance(boss.position, target) < 15, "the Devourer rose more than 15 tiles from the marked point")
          done()
          return false
        elseif game.tick > rise_at + 60 then
          error("the Devourer did not rise after its telegraph expired")
        end
      end
    end)
  end)
end)
