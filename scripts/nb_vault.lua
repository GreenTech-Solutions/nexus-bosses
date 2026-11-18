-- The vault is marked for a force after it defeats all three bosses of the Convergence. Its four-part code is entered
-- at a console; earned glyphs and every third wrong code reveal the next code place for that force.
-- The reliquary consumes a warp key to research Silence when that technology exists. Without that gate, the relic is
-- placed in the vault as soon as it is built. The relic researches the Echo of the builders when mined.
--
--   storage.vault.ruin          the vault ruin (LuaEntity), position
--   storage.vault.code          {glyph index, ...} in the order of the code
--   storage.vault.obelisks      {LuaEntity, ...} in the order of the code (they stand in another order)
--   storage.vault.console, hatch, stairs, reliquary, relic
--   storage.vault.open          the lock is open (for everybody: the vault is one)
--   storage.vault.marked        [force_name] = true
--   storage.vault.attempts      [force_name] = wrong codes
--   storage.vault.earned        [force_name] = {[source] = true}
--   storage.vault.revealed      [force_name] = {[place] = true}
--   storage.vault.built         the surface of the vault is built

local cfg = require("lib.nb_data")
local util = require("scripts.nb_util")
local progress = require("scripts.nb_progress")
local story = require("scripts.nb_story")

local M = {}

local BLINK_TICKS = 60 -- an obelisk is lit this long, then the next one
local DARK_STEPS = 2 -- a pause after the four, so the order has a start
local HINT_EVERY = 3
local SIZE = 256
local GLOW = { r = 0.65, g = 0.5, b = 1 }

-- the halls of the vault, west to east, as {x1, y1, x2, y2}; a corridor runs between neighbours along y = 0
---@type integer[][]
local HALLS = {
  { -110, -10, -86, 10 }, -- the stairs
  { -62, -12, -38, 12 }, -- the builders' remains
  { -16, -16, 16, 16 }, -- the pylon hall
  { 38, -12, 62, 12 }, -- the glyph gallery
  { 84, -16, 112, 16 }, -- the treasure
}
local FLOOR = "fulgoran-paving"
local CORRIDOR = "fulgoran-conduit"

function M.init()
  storage.vault = storage.vault or {}
  local v = storage.vault
  v.obelisks = v.obelisks or {}
  v.marked = v.marked or {}
  v.attempts = v.attempts or {}
  v.earned = v.earned or {}
  v.revealed = v.revealed or {}
end

---@return LuaSurface|nil
local function vault_surface()
  return game.get_surface(cfg.VAULT_SURFACE)
end

---@param index integer
---@return string
local function glyph(index)
  return cfg.GLYPH_PREFIX .. index
end

---@param index integer
---@return string rich text of a glyph
local function glyph_text(index)
  return "[virtual-signal=" .. glyph(index) .. "]"
end

---Whether the warp-drive gate adds Silence to the technology tree.
---@return boolean
local function gated()
  return prototypes.technology[cfg.SILENCE_TECH] ~= nil
end

---Place the relic once on the vault surface.
---@param surface LuaSurface
---@return LuaEntity|nil
local function raise_relic(surface)
  local v = storage.vault
  if v.relic and v.relic.valid then
    return v.relic
  end
  local relic = surface.create_entity({ name = cfg.RELIC, position = { x = 104, y = 0 }, force = "neutral" })
  if relic then
    relic.destructible = false
    v.relic = relic
    rendering.draw_animation({ animation = "nexus-bosses-summon-circle", target = relic, surface = surface,
      tint = { r = 1, g = 0.75, b = 0.35 }, render_layer = "lower-object" })
  end
  return relic
end

---Reveals the next code places earned by a force and its wrong-code hints.
---@param force LuaForce
local function reveal(force)
  local v = storage.vault
  if not v.code then
    return
  end
  local earned = v.earned[force.name] or {}
  local earned_count = 0
  for _ in pairs(earned) do
    earned_count = earned_count + 1
  end
  local hints = math.floor((v.attempts[force.name] or 0) / HINT_EVERY)
  local target = math.min(cfg.CODE_LENGTH, earned_count + hints)
  local revealed = v.revealed[force.name] or {}
  v.revealed[force.name] = revealed
  local revealed_count = 0
  for _ in pairs(revealed) do
    revealed_count = revealed_count + 1
  end
  for place = 1, cfg.CODE_LENGTH do
    if revealed_count >= target then
      break
    end
    if not revealed[place] then
      revealed[place] = true
      revealed_count = revealed_count + 1
      util.say(force, { "nexus-bosses.msg-vault-hint", place, glyph_text(v.code[place]) }, util.COLORS.info)
      util.play(force, "detector")
    end
  end
end

---A force earned one glyph source. Repeated finds of the same source count once.
---@param force LuaForce
---@param source "camp"|"logs"|"lair"|"badge"
---@return boolean true if this source was newly earned
function M.earn(force, source)
  local v = storage.vault
  local earned = v.earned[force.name] or {}
  v.earned[force.name] = earned
  if earned[source] then
    return false
  end
  earned[source] = true
  reveal(force)
  return true
end

-- The lock --------------------------------------------------------------------------------------------------------

---The vault ruin nearest to the spawn in the ring, in generated land; failing that, one of its own on the ring.
---@param surface LuaSurface
---@return LuaEntity|nil
local function find_ruin(surface)
  local center = game.forces.player.get_spawn_position(surface)
  local best, best_distance
  for _, ruin in ipairs(surface.find_entities_filtered({ name = cfg.VAULT_RUIN })) do
    local distance = util.distance(center, ruin.position)
    if distance >= cfg.VAULT_RING[1] and distance <= cfg.VAULT_RING[2] and (not best_distance or distance < best_distance) then
      best, best_distance = ruin, distance
    end
  end
  if best then
    return best
  end
  local seed = ((surface.map_gen_settings.seed or 0) + 4241) % 4294967296
  local rng = game.create_random_generator(seed --[[@as uint32]])
  local wanted = util.offset(center, rng() * 2 * math.pi, rng(cfg.VAULT_RING[1] + 100, cfg.VAULT_RING[1] + 300))
  util.ensure_generated(surface, wanted)
  local position = surface.find_non_colliding_position(cfg.VAULT_RUIN, wanted, 60, 1)
  return position and surface.create_entity({ name = cfg.VAULT_RUIN, position = position })
end

---The obelisks, the console and their glyphs around the ruin, once.
---@param surface LuaSurface
local function build_lock(surface)
  local v = storage.vault
  if v.ruin and v.ruin.valid then
    return
  end
  local ruin = find_ruin(surface)
  if not ruin then
    log("[nexus-bosses] no vault ruin for the glyph lock")
    return
  end
  ruin.destructible = false
  ruin.minable_flag = false
  v.ruin = ruin
  v.position = util.copy_position(ruin.position)
  local rng = game.create_random_generator(((surface.map_gen_settings.seed or 0) + 8513) % 4294967296 --[[@as uint32]])
  local pool = {}
  for index = 1, cfg.GLYPHS do
    pool[index] = index
  end
  v.code = {}
  for place = 1, cfg.CODE_LENGTH do
    v.code[place] = table.remove(pool, rng(1, #pool) --[[@as integer]])
  end
  -- the obelisks stand south of the ruin in a shuffled order: where one stands says nothing of its place in the code
  local order = {}
  for place = 1, cfg.CODE_LENGTH do
    table.insert(order, rng(1, #order + 1) --[[@as integer]], place)
  end
  local x, y = util.xy(ruin.position)
  v.obelisks = {}
  for slot, place in ipairs(order) do
    local wanted = { x = x - 15 + slot * 6, y = y + 10 }
    local spot = surface.find_non_colliding_position(cfg.OBELISK, wanted, 6, 0.5) or wanted
    local obelisk = surface.create_entity({ name = cfg.OBELISK, position = spot, force = "neutral" })
    if obelisk then
      obelisk.destructible = false
      obelisk.minable_flag = false
      v.obelisks[place] = obelisk
      rendering.draw_sprite({ sprite = "virtual-signal/" .. glyph(v.code[place]), target = { entity = obelisk, offset = { 0, -2.6 } },
        surface = surface, x_scale = 1.6, y_scale = 1.6, tint = { r = 0.55, g = 0.5, b = 0.65, a = 0.8 } })
    end
  end
  local spot = surface.find_non_colliding_position(cfg.CONSOLE, { x = x, y = y + 15 }, 8, 0.5)
  local console = spot and surface.create_entity({ name = cfg.CONSOLE, position = spot, force = "player" })
  if console then
    console.destructible = false
    console.minable_flag = false
    v.console = console
  end
end

---The hatch next to the console, once the lock is open.
---@param surface LuaSurface
local function raise_hatch(surface)
  local v = storage.vault
  if (v.hatch and v.hatch.valid) or not v.position then
    return
  end
  local wanted = { x = v.position.x + 12, y = v.position.y + 15 }
  local spot = surface.find_non_colliding_position(cfg.HATCH, wanted, 10, 0.5) or wanted
  local hatch = surface.create_entity({ name = cfg.HATCH, position = spot, force = "neutral" })
  if hatch then
    hatch.destructible = false
    hatch.minable_flag = false
    v.hatch = hatch
    rendering.draw_animation({ animation = "nexus-bosses-summon-circle", target = hatch, surface = surface, tint = GLOW,
      render_layer = "lower-object", x_scale = 1.4, y_scale = 1.4 })
    rendering.draw_light({ sprite = "utility/light_medium", target = hatch, surface = surface, scale = 5, intensity = 0.9,
      color = GLOW })
  end
end

---@param announce boolean
local function open_lock(announce)
  local v = storage.vault
  if v.open then
    return
  end
  v.open = true
  local surface = util.nexus()
  if surface then
    raise_hatch(surface)
  end
  if announce then
    for force_name in pairs(v.marked) do
      local force = game.forces[force_name]
      if force then
        util.say(force, { "nexus-bosses.msg-vault-open" }, util.COLORS.good)
        util.play(force, "silence")
      end
    end
  end
end

---The vault is marked for a force that defeated all three bosses of the Convergence.
---@param force LuaForce
function M.sync(force)
  local surface = util.nexus()
  local v = storage.vault
  if not surface or force.name == "enemy" or force.name == "neutral" or v.marked[force.name]
    or not progress.circle_done(force.name, #cfg.CIRCLES) then
    return
  end
  build_lock(surface)
  if not v.position then
    return
  end
  v.marked[force.name] = true
  local x, y = util.xy(v.position)
  force.chart(surface, { { x - 40, y - 40 }, { x + 40, y + 40 } })
  force.add_chart_tag(surface, { position = v.position, icon = { type = "virtual", name = glyph(v.code[1]) } })
  util.say(force, { "nexus-bosses.msg-vault-revealed", math.floor(x), math.floor(y), surface.name }, util.COLORS.info)
  reveal(force)
  if settings.global["nexus-bosses-skip-glyph-lock"].value then
    open_lock(true)
  end
end

function M.sync_all()
  for _, force in pairs(game.forces) do
    M.sync(force)
  end
end

---The glyphs set in the console: {[glyph index] = value}.
---@return table<integer, integer>
local function console_glyphs()
  local set = {}
  local console = storage.vault.console
  local behavior = console and console.valid and console.get_control_behavior() --[[@as LuaConstantCombinatorControlBehavior?]]
  if not behavior then
    return set
  end
  for _, section in ipairs(behavior.sections) do
    if section.active then
      for _, filter in ipairs(section.filters) do
        local value = filter.value
        local name = value and value.name
        if name and name:sub(1, #cfg.GLYPH_PREFIX) == cfg.GLYPH_PREFIX then
          local index = tonumber(name:sub(#cfg.GLYPH_PREFIX + 1))
          if index then
            set[index] = (set[index] or 0) + (filter.min or 0)
          end
        end
      end
    end
  end
  return set
end

---@param set table<integer, integer>
---@return boolean
local function code_matches(set)
  local code = storage.vault.code
  for index, value in pairs(set) do
    if value ~= 0 then
      local place
      for p, g in ipairs(code) do
        if g == index then
          place = p
        end
      end
      if place ~= value then
        return false
      end
    end
  end
  for place, g in ipairs(code) do
    if set[g] ~= place then
      return false
    end
  end
  return true
end

---A player closed the console: the code is tried.
---@param player LuaPlayer
function M.on_console_closed(player)
  local v = storage.vault
  if v.open or not v.code then
    return
  end
  local set = console_glyphs()
  if next(set) == nil then
    return
  end
  if code_matches(set) then
    open_lock(true)
    return
  end
  local force = player.force --[[@as LuaForce]]
  local attempts = (v.attempts[force.name] or 0) + 1
  v.attempts[force.name] = attempts
  util.say(force, { "nexus-bosses.msg-vault-wrong" }, util.COLORS.warning)
  reveal(force)
end

---The obelisks light up one after another, in the order of the code. Once a second.
---@param tick integer
function M.on_second(tick)
  local v = storage.vault
  if v.open or not v.code or #v.obelisks == 0 then
    return
  end
  local step = math.floor(tick / BLINK_TICKS) % (cfg.CODE_LENGTH + DARK_STEPS) + 1
  local obelisk = v.obelisks[step]
  if obelisk and obelisk.valid then
    rendering.draw_light({ sprite = "utility/light_medium", target = obelisk, surface = obelisk.surface, scale = 3,
      intensity = 1, color = GLOW, time_to_live = BLINK_TICKS })
    rendering.draw_sprite({ sprite = "virtual-signal/" .. glyph(v.code[step]), target = { entity = obelisk, offset = { 0, -2.6 } },
      surface = obelisk.surface, x_scale = 2, y_scale = 2, time_to_live = BLINK_TICKS, render_layer = "light-effect" })
  end
end

-- The vault ------------------------------------------------------------------------------------------------------------

---@param tiles table[]
---@param x1 integer
---@param y1 integer
---@param x2 integer
---@param y2 integer
---@param name string
local function fill(tiles, x1, y1, x2, y2, name)
  for x = x1, x2 - 1 do
    for y = y1, y2 - 1 do
      tiles[#tiles + 1] = { name = name, position = { x, y } }
    end
  end
end

---@param surface LuaSurface
---@param name string
---@param position MapPosition
---@return LuaEntity|nil
local function put(surface, name, position)
  local entity = surface.create_entity({ name = name, position = position, force = "neutral" })
  if entity then
    entity.destructible = false
    if entity.type ~= "simple-entity" or entity.name ~= cfg.RELIC then
      entity.minable_flag = false
    end
  end
  return entity
end

---The halls, their remains and the treasure, once.
---@return LuaSurface
local function build_vault()
  local surface = vault_surface()
  if not surface then
    surface = game.create_surface(cfg.VAULT_SURFACE, {
      width = SIZE,
      height = SIZE,
      default_enable_all_autoplace_controls = false,
      autoplace_settings = {
        tile = { treat_missing_as_default = false, settings = {} },
        entity = { treat_missing_as_default = false, settings = {} },
        decorative = { treat_missing_as_default = false, settings = {} },
      },
    })
    surface.freeze_daytime = true
    surface.daytime = 0.5
    surface.show_clouds = false
    surface.request_to_generate_chunks({ 0, 0 }, SIZE / 64 + 1)
    surface.force_generate_chunk_requests()
  end
  local v = storage.vault
  if v.built then
    return surface
  end
  v.built = true
  local tiles = {}
  fill(tiles, -SIZE / 2, -SIZE / 2, SIZE / 2, SIZE / 2, "out-of-map")
  surface.set_tiles(tiles, true, false, false, false)
  tiles = {}
  for index, hall in ipairs(HALLS) do
    fill(tiles, hall[1], hall[2], hall[3], hall[4], FLOOR)
    local next_hall = HALLS[index + 1]
    if next_hall then
      fill(tiles, hall[3], -2, next_hall[1], 2, CORRIDOR)
    end
  end
  surface.set_tiles(tiles, true, false, false, false)

  -- the stairs up
  v.stairs = put(surface, cfg.STAIRS, { x = -105, y = 0 })
  if v.stairs then
    rendering.draw_light({ sprite = "utility/light_medium", target = v.stairs, surface = surface, scale = 4, intensity = 0.7,
      color = GLOW })
  end
  -- the remains of the builders: the same layout in every game
  local rng = game.create_random_generator(7351)
  ---@type string[]
  local RUINS = { "fulgoran-ruin-small", "fulgoran-ruin-small", "fulgoran-ruin-medium", "fulgoran-ruin-medium",
    "fulgoran-ruin-big", "fulgoran-ruin-huge" }
  for index = 2, 4 do
    local hall = HALLS[index] --[[@as integer[] ]]
    for _ = 1, 9 do
      local name = RUINS[rng(1, #RUINS) --[[@as integer]]]
      local wanted = { x = rng(hall[1] + 3, hall[3] - 3), y = rng(hall[2] + 3, hall[4] - 3) }
      -- the middle of a hall and the line of the corridor stay free
      if prototypes.entity[name] and math.abs(wanted.y) > 3 then
        local spot = surface.find_non_colliding_position(name, wanted, 4, 1)
        if spot then
          put(surface, name, spot)
        end
      end
    end
  end
  if prototypes.entity["fulgoran-ruin-stonehenge"] then
    put(surface, "fulgoran-ruin-stonehenge", { x = 0, y = 0 })
  end
  for index = 1, #HALLS - 1 do
    local from = (HALLS[index] --[[@as integer[] ]])[3]
    local to = (HALLS[index + 1] --[[@as integer[] ]])[1]
    for x = from + 4, to - 4, 8 do
      rendering.draw_light({ sprite = "utility/light_small", target = { x = x, y = 0 }, surface = surface, scale = 2,
        intensity = 0.45, color = GLOW })
    end
  end
  -- the gallery of the glyphs: every glyph on an obelisk, dim
  for index = 1, cfg.GLYPHS do
    local x = 40 + ((index - 1) % 4) * 6
    local y = index <= 4 and -8 or 8
    local obelisk = put(surface, cfg.OBELISK, { x = x, y = y })
    if obelisk then
      rendering.draw_sprite({ sprite = "virtual-signal/" .. glyph(index), target = { entity = obelisk, offset = { 0, -2.6 } },
        surface = surface, x_scale = 1.6, y_scale = 1.6, tint = { r = 0.6, g = 0.55, b = 0.75, a = 0.85 } })
      rendering.draw_light({ sprite = "utility/light_small", target = obelisk, surface = surface, scale = 2, intensity = 0.5,
        color = GLOW })
    end
  end
  -- the treasure
  v.reliquary = put(surface, cfg.RELIQUARY, { x = 98, y = 0 })
  if v.reliquary then
    rendering.draw_light({ sprite = "utility/light_medium", target = v.reliquary, surface = surface, scale = 6,
      intensity = 1, color = { r = 1, g = 0.8, b = 0.45 } })
  end
  if not gated() then
    raise_relic(surface)
  end
  return surface
end

---@param player LuaPlayer
---@param surface LuaSurface
---@param position MapPosition
local function move(player, surface, position)
  if player.driving then
    player.driving = false
  end
  local spot = surface.find_non_colliding_position("character", position, 10, 0.5) or position
  player.teleport(spot, surface)
end

---A player opened the hatch: down into the vault.
---@param player LuaPlayer
function M.descend(player)
  player.opened = nil
  if not (storage.vault.open and player.character) then
    return
  end
  local surface = build_vault()
  move(player, surface, { x = -100, y = 0 })
  player.play_music({ name = cfg.VAULT_TRACK, fade_in_duration = 120, fade_out_duration = 120 })
  util.say(player, { "nexus-bosses.msg-vault-enter" }, util.COLORS.info)
end

---A player opened the stairs: back up next to the hatch.
---@param player LuaPlayer
function M.ascend(player)
  player.opened = nil
  local surface = util.nexus()
  local hatch = storage.vault.hatch
  if surface and hatch and hatch.valid then
    local x, y = util.xy(hatch.position)
    move(player, surface, { x = x, y = y + 3 })
  end
end

---A player who died in the vault comes back at the hatch.
---@param player LuaPlayer
function M.on_respawned(player)
  if player.surface.name == cfg.VAULT_SURFACE then
    M.ascend(player)
  end
end

---A player opened the reliquary: the last log of the story.
---@param player LuaPlayer
function M.on_reliquary_opened(player)
  local force = player.force --[[@as LuaForce]]
  if story.is_found(force.name, "vault") then
    return
  end
  story.find(force.name, "vault")
  util.say(force, { "nexus-bosses.msg-vault-log-found" }, util.COLORS.good)
  util.play(force, "trophy")
end

---A player closed the reliquary: a warp key researches Silence.
---@param player LuaPlayer
function M.on_reliquary_closed(player)
  local v = storage.vault
  local reliquary = v.reliquary
  if not (reliquary and reliquary.valid) then
    return
  end
  local force = player.force --[[@as LuaForce]]
  local technology = force.technologies[cfg.SILENCE_TECH]
  if not technology or technology.researched then
    return
  end
  local inventory = reliquary.get_inventory(defines.inventory.chest)
  if not inventory then
    return
  end
  local key
  for _, entry in ipairs(inventory.get_contents()) do
    if entry.name == cfg.WARP_KEY then
      key = entry
      break
    end
  end
  if not key or inventory.remove({ name = cfg.WARP_KEY, quality = key.quality, count = 1 }) == 0 then
    return
  end
  progress.research(force, cfg.SILENCE_TECH)
  util.say(force, { "nexus-bosses.msg-vault-key-accepted" }, util.COLORS.good)
  util.play(force, "silence")
  raise_relic(reliquary.surface)
end

---A player opened the console: a commander's badge earns one glyph.
---@param player LuaPlayer
function M.on_console_opened(player)
  local inventory = player.get_main_inventory()
  if not inventory or inventory.get_item_count(cfg.BADGE) == 0 then
    return
  end
  local force = player.force --[[@as LuaForce]]
  local earned = storage.vault.earned[force.name]
  if earned and earned.badge then
    return
  end
  if inventory.remove({ name = cfg.BADGE, count = 1 }) == 0 then
    return
  end
  M.earn(force, "badge")
  util.say(force, { "nexus-bosses.msg-vault-badge" }, util.COLORS.good)
end

---@param technology LuaTechnology
function M.on_research_finished(technology)
  if technology.name == cfg.ECHO_TECH then
    util.say(technology.force, { "nexus-bosses.msg-builders-echo" }, util.COLORS.good)
    util.play(technology.force, "silence")
  end
end

---@param event EventData.on_runtime_mod_setting_changed
function M.on_settings_changed(event)
  if event.setting == "nexus-bosses-skip-glyph-lock" and settings.global["nexus-bosses-skip-glyph-lock"].value
    and next(storage.vault.marked) then
    open_lock(true)
  end
end

---@return table
function M.snapshot()
  local v = storage.vault
  local obelisks = {}
  for place, obelisk in pairs(v.obelisks) do
    obelisks[place] = obelisk.valid and { x = obelisk.position.x, y = obelisk.position.y } or false
  end
  return {
    position = v.position,
    code = v.code,
    open = v.open == true,
    marked = v.marked,
    attempts = v.attempts,
    earned = v.earned,
    revealed = v.revealed,
    built = v.built == true,
    obelisks = obelisks,
    console = v.console and v.console.valid and { x = v.console.position.x, y = v.console.position.y } or nil,
    hatch = v.hatch and v.hatch.valid and { x = v.hatch.position.x, y = v.hatch.position.y } or nil,
    relic = v.relic and v.relic.valid or false,
  }
end

return M
