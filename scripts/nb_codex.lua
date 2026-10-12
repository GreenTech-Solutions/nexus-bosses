-- The codex of the signal: the stages and their bosses on the left (killed, log found), the page of the chosen boss on
-- the right. Without its log a boss is only a name: the dossier, how to fight it, is in the log of the expedition.

local cfg = require("lib.nb_data")
local progress = require("scripts.nb_progress")
local expedition = require("scripts.nb_expedition")
local bearing = require("scripts.nb_bearing")

local M = {}

local NAME = "nexus_bosses_codex"
local CLOSE = "nexus_bosses_codex_close"
local BOSS = "nexus_bosses_codex_boss_"
local PAGE_WIDTH = 440

---@param player LuaPlayer
---@return LuaGuiElement|nil
local function frame_of(player)
  return player.gui.screen[NAME]
end

---@param parent LuaGuiElement
---@param caption LocalisedString
---@param style string|nil
local function paragraph(parent, caption, style)
  local label = parent.add({ type = "label", caption = caption, style = style })
  label.style.single_line = false
  label.style.maximal_width = PAGE_WIDTH
  return label
end

---@param page LuaGuiElement
---@param force_name string
---@param boss_id string
local function fill_page(page, force_name, boss_id)
  page.clear()
  local boss = cfg.BOSSES[boss_id]
  local stage = cfg.CIRCLES[boss.circle].stage
  paragraph(page, { "", { "nexus-bosses.boss-" .. boss_id }, " · ", { "nexus-bosses.stage-" .. stage } }, "heading_2_label")
  paragraph(page, { "nexus-bosses.lore-" .. boss_id })
  page.add({ type = "line" })
  if expedition.has_log(force_name, boss_id) then
    paragraph(page, { "nexus-bosses.log-" .. boss_id })
  else
    paragraph(page, { "nexus-bosses.codex-no-log" }).style.font_color = { r = 0.6, g = 0.6, b = 0.6 }
  end
  page.add({ type = "line" })
  paragraph(page, { progress.is_defeated(force_name, boss_id) and "nexus-bosses.codex-defeated" or "nexus-bosses.codex-alive" })
  local lair = bearing.lair_position(boss_id)
  if lair and bearing.is_found(force_name, boss_id) then
    local x, y = lair.x, lair.y
    local quality = bearing.next_quality(force_name, boss_id)
    paragraph(page, { "nexus-bosses.codex-lair", math.floor(x), math.floor(y), cfg.PLANET, bearing.wins_of(force_name, boss_id),
      string.format("[item=%s,quality=%s]", cfg.trophy_name(boss_id), quality) })
  else
    local technology = game.forces[force_name].technologies[cfg.BEARING_TECH]
    if technology and technology.researched then
      paragraph(page, { "nexus-bosses.codex-no-lair" }).style.font_color = { r = 0.6, g = 0.6, b = 0.6 }
    end
  end
end

---@param player LuaPlayer
---@param selected string|nil boss id
function M.open(player, selected)
  local old = frame_of(player)
  if old then
    old.destroy()
  end
  local force_name = player.force.name --[[@as string]]
  selected = selected or cfg.ORDER[1] --[[@as string]]

  local frame = player.gui.screen.add({ type = "frame", name = NAME, direction = "vertical" })
  local titlebar = frame.add({ type = "flow", direction = "horizontal" })
  titlebar.drag_target = frame
  titlebar.add({ type = "label", caption = { "nexus-bosses.codex-title" }, style = "frame_title", ignored_by_interaction = true })
  local filler = titlebar.add({ type = "empty-widget", style = "draggable_space_header", ignored_by_interaction = true })
  filler.style.horizontally_stretchable = true
  filler.style.height = 24
  titlebar.add({ type = "sprite-button", name = CLOSE, sprite = "utility/close", style = "frame_action_button" })

  local body = frame.add({ type = "flow", direction = "horizontal" })
  local list = body.add({ type = "frame", direction = "vertical", style = "inside_deep_frame" })
  list.style.padding = 8
  for _, circle in ipairs(cfg.CIRCLES) do
    list.add({ type = "label", caption = { "nexus-bosses.stage-" .. circle.stage }, style = "caption_label" })
    for _, id in ipairs(circle.bosses) do
      local marks = (progress.is_defeated(force_name, id) and "[img=utility/check_mark_green] " or "")
        .. (expedition.has_log(force_name, id) and "[item=nexus-trophy-" .. id .. "] " or "")
      local button = list.add({
        type = "button",
        name = BOSS .. id,
        caption = { "", marks, { "nexus-bosses.boss-" .. id } },
        tags = { boss = id },
      })
      button.style.horizontally_stretchable = true
      button.style.minimal_width = 220
      button.toggled = id == selected
    end
  end
  local page = body.add({ type = "frame", name = "page", direction = "vertical", style = "inside_shallow_frame_with_padding" })
  page.style.width = PAGE_WIDTH + 24
  page.style.vertically_stretchable = true
  fill_page(page, force_name, selected)

  frame.force_auto_center()
  player.opened = frame
end

---@param player LuaPlayer
function M.toggle(player)
  local frame = frame_of(player)
  if frame then
    frame.destroy()
  else
    M.open(player)
  end
end

---@param event EventData.on_gui_click
function M.on_gui_click(event)
  local element = event.element
  if not (element and element.valid) then
    return
  end
  local player = game.get_player(event.player_index) --[[@as LuaPlayer]]
  if element.name == CLOSE then
    local frame = frame_of(player)
    if frame then
      frame.destroy()
    end
  elseif element.name:sub(1, #BOSS) == BOSS then
    M.open(player, element.tags.boss --[[@as string]])
  end
end

---@param event EventData.on_gui_closed
function M.on_gui_closed(event)
  local element = event.element
  if element and element.valid and element.name == NAME then
    element.destroy()
  end
end

return M
