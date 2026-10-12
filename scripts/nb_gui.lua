-- The health bar of the boss at the top of the screen, for the players of the force of the trial. Rebuilt for
-- players who join during the fight; the bar is the health of the required entities against their health when they
-- appeared.

local M = {}

local NAME = "nexus_bosses_health"
local WIDTH = 460

---@param player LuaPlayer
---@return LuaGuiElement
local function create(player)
  local frame = player.gui.screen.add({ type = "frame", name = NAME, direction = "vertical" })
  frame.style.width = WIDTH
  frame.ignored_by_interaction = true
  local title = frame.add({ type = "label", name = "title", style = "frame_title" })
  title.style.horizontally_stretchable = true
  local bar = frame.add({ type = "progressbar", name = "bar", value = 1 })
  bar.style.horizontally_stretchable = true
  bar.style.color = { r = 0.85, g = 0.2, b = 0.15 }
  frame.add({ type = "label", name = "status" })
  local scale = player.display_scale
  frame.location = { x = math.floor((player.display_resolution.width - WIDTH * scale) / 2), y = math.floor(48 * scale) }
  return frame
end

---@param force LuaForce
---@param title LocalisedString
---@param share number 0..1
---@param status LocalisedString|nil
function M.update(force, title, share, status)
  for _, player in ipairs(force.connected_players) do
    local frame = player.gui.screen[NAME] or create(player)
    frame.title.caption = title
    frame.bar.value = share
    frame.status.caption = status or ""
    frame.status.visible = status ~= nil
  end
end

---@param force LuaForce
function M.destroy(force)
  for _, player in pairs(force.players) do
    local frame = player.gui.screen[NAME]
    if frame then
      frame.destroy()
    end
  end
end

return M
