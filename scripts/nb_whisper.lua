-- Hallucinations of the Whisper. At night on Nexus, far from anything the force has built, the signal plays with
-- the player: a shade of a precursor at the edge of the screen walks away and is gone, a whisper in the chat with a
-- faint sound, a false alarm (now and then it whispers where an unfound wreck of the expedition really lies), the edges
-- of the screen darkening. The deeper the stage, the more often; after Silence, nothing. Everything is for that player
-- only, except the shade, a real neutral unit that others nearby would see too. The per-player setting
-- nexus-bosses-hallucinations turns it down or off.
-- Average intervals by stage are 10 minutes on Whisper and 5 minutes on Chorus and Convergence.
--
--   storage.whisper.next     [player_index] = tick of the next hallucination
--   storage.whisper.shades   [unit_number] = {entity, until}

local cfg = require("lib.nb_data")
local util = require("scripts.nb_util")
local progress = require("scripts.nb_progress")
local expedition = require("scripts.nb_expedition")

local M = {}

M.CHECK_TICKS = 300
-- seconds between hallucinations by stage (Whisper, Chorus, Convergence)
local INTERVALS = { 600, 300, 300 }
local RARE_FACTOR = 2
local LINES = 3 -- whisper-<stage>-1..LINES in the locale
local NIGHT = 0.5 -- darkness of the surface
local WHISPER_COLOR = { r = 0.6, g = 0.55, b = 0.7 }
local LONELY_RADIUS = 64
local SHADE_TICKS = 180
-- the shade stands near the edge of what the player sees at the default zoom (the screen is wider than tall)
local SHADE_RADIUS = { x = 22, y = 11 }
local MOBILE = { "character", "car", "spider-vehicle", "locomotive", "cargo-wagon", "fluid-wagon", "artillery-wagon" }

function M.init()
  storage.whisper = storage.whisper or {}
  storage.whisper.next = storage.whisper.next or {}
  storage.whisper.shades = storage.whisper.shades or {}
end

---The stage that whispers to a force: the last one opened, none after Silence.
---@param force LuaForce
---@return integer|nil
local function stage_of(force)
  if progress.story_ended(force) then
    return nil
  end
  for index = #cfg.CIRCLES, 1, -1 do
    local technology = force.technologies[cfg.CIRCLES[index].tech]
    if technology and technology.researched then
      return index
    end
  end
  return nil
end

---No building of the force near the character.
---@param surface LuaSurface
---@param force LuaForce
---@param position MapPosition
---@return boolean
local function lonely(surface, force, position)
  local all = surface.count_entities_filtered({ position = position, radius = LONELY_RADIUS, force = force, limit = 50 })
  local mobile = surface.count_entities_filtered({ position = position, radius = LONELY_RADIUS, force = force, type = MOBILE,
    limit = 50 })
  return all - mobile == 0
end

---A precursor of the stage that walks away and is gone.
---@param player LuaPlayer
---@param surface LuaSurface
---@param stage integer
---@return LuaEntity|nil
local function shade(player, surface, stage)
  local bosses = cfg.CIRCLES[stage].bosses
  local boss = cfg.BOSSES[bosses[math.random(#bosses)]]
  local name = boss.precursors[math.random(#boss.precursors)]
  local angle = math.random() * 2 * math.pi
  local px, py = util.xy(player.position)
  local wanted = { x = px + math.cos(angle) * SHADE_RADIUS.x, y = py + math.sin(angle) * SHADE_RADIUS.y }
  local spot = surface.find_non_colliding_position(name, wanted, 6, 0.5)
  if not spot then
    return nil
  end
  local unit = surface.create_entity({ name = name, position = spot, force = "neutral" })
  if not unit then
    return nil
  end
  unit.destructible = false
  local commandable = unit.commandable
  if commandable then
    commandable.set_command({
      type = defines.command.go_to_location,
      destination = util.offset(spot, angle, 30),
      distraction = defines.distraction.none,
      radius = 2,
    })
  end
  storage.whisper.shades[unit.unit_number] = { entity = unit, ["until"] = game.tick + SHADE_TICKS }
  return unit
end

---@param player LuaPlayer
local function vignette(player)
  local character = player.character --[[@as LuaEntity]]
  rendering.draw_sprite({
    sprite = "nexus-bosses-vignette",
    target = character,
    surface = character.surface,
    players = { player },
    x_scale = 5,
    y_scale = 5,
    tint = { r = 1, g = 1, b = 1, a = 0.75 },
    render_layer = "cursor",
    time_to_live = 60,
  })
end

---@param player LuaPlayer
---@param stage integer
local function whisper(player, stage)
  local line = { "nexus-bosses.whisper-" .. cfg.CIRCLES[stage].stage .. "-" .. math.random(LINES) }
  player.print({ "", "[font=default-italic]", line, "[/font]" }, { color = WHISPER_COLOR, sound = defines.print_sound.never })
  player.play_sound({
    path = "nexus-bosses-precursors",
    position = util.offset(player.position, math.random() * 2 * math.pi, 20),
    volume_modifier = 0.3,
  })
end

---An alarm on a shade; now and then it whispers where an unfound wreck really is.
---@param player LuaPlayer
---@param surface LuaSurface
---@param stage integer
local function false_alarm(player, surface, stage)
  local unit = shade(player, surface, stage)
  if unit then
    player.add_custom_alert(unit, { type = "entity", name = unit.name }, { "nexus-bosses.alert-hallucination" }, true)
  end
  if math.random() < 0.3 then
    local position = expedition.unfound_wreck(player.force.name --[[@as string]])
    if position then
      local x, y = util.xy(position)
      player.print({ "nexus-bosses.whisper-wreck", math.floor(x), math.floor(y), surface.name }, { color = WHISPER_COLOR })
    end
  end
end

---@param player LuaPlayer
---@param surface LuaSurface
---@param stage integer
---@param kind integer|nil 1 shade, 2 whisper, 3 false alarm, 4 vignette and whisper; nil: any of them
local function hallucinate(player, surface, stage, kind)
  kind = kind or math.random(4)
  if kind == 1 or kind == 3 then
    player.play_music({ name = "nexus-bosses-hallucination", fade_in_duration = 120, fade_out_duration = 120 })
  end
  if kind == 1 then
    shade(player, surface, stage)
    vignette(player)
  elseif kind == 2 then
    whisper(player, stage)
  elseif kind == 3 then
    false_alarm(player, surface, stage)
  else
    vignette(player)
    whisper(player, stage)
  end
end

---The shades whose time is up are gone. Every half a second.
---@param tick integer
function M.clear_shades(tick)
  local shades = storage.whisper.shades
  if next(shades) == nil then
    return
  end
  for unit, entry in pairs(shades) do
    if tick >= entry["until"] or not entry.entity.valid then
      if entry.entity.valid then
        entry.entity.destroy()
      end
      shades[unit] = nil
    end
  end
end

---Every CHECK_TICKS.
---@param tick integer
function M.on_tick(tick)
  local w = storage.whisper
  local surface = util.nexus()
  if not surface or surface.darkness < NIGHT then
    return
  end
  for _, player in pairs(game.connected_players) do
    local character = player.character
    local mode = settings.get_player_settings(player)["nexus-bosses-hallucinations"].value
    if character and character.surface_index == surface.index and mode ~= "off" then
      local force = player.force --[[@as LuaForce]]
      local stage = stage_of(force)
      if stage and lonely(surface, force, character.position) then
        local interval = (INTERVALS[stage] or INTERVALS[1]) * 60 * (mode == "rare" and RARE_FACTOR or 1)
        local due = w.next[player.index]
        if not due then
          w.next[player.index] = tick + math.floor(interval * (0.5 + math.random()))
        elseif tick >= due then
          w.next[player.index] = tick + math.floor(interval * (0.5 + math.random()))
          hallucinate(player, surface, stage)
        end
      end
    end
  end
end

---For tests: a hallucination for a player now, whatever the time and place.
---@param player LuaPlayer
---@param kind integer|nil 1 shade, 2 whisper, 3 false alarm, 4 vignette and whisper
function M.force(player, kind)
  local surface = util.nexus()
  local stage = stage_of(player.force --[[@as LuaForce]]) or 1
  if not (surface and player.character) then
    return
  end
  hallucinate(player, surface, stage, kind)
end

return M
