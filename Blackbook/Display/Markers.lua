-- Blackbook: how each verdict looks (section 6.6): the chat icon, the target
-- frame overlay and the tooltip colour all read this one table.
local _, ns = ...

local Markers = {}
ns.Markers = Markers

-- color: tooltip text colour. strike: draw a diagonal bar over the portrait.
-- icon: texture shown in chat and in the portrait corner; tint recolours it.
Markers.Look = {
  ignore = { color = { 1, 0.33, 0.33 }, strike = true },
  warn = { color = { 1, 0.67, 0.2 }, icon = "Interface/DialogFrame/UI-Dialog-Icon-AlertNew" },
  notice = { color = { 0.4, 0.73, 1 }, icon = "Interface/Buttons/Arrow-Down-Up", tint = { 0.3, 0.6, 1 } },
}

local RED_CROSS = "|cffe61a1a" .. string.char(195, 151) .. "|r" -- a red multiplication sign

local function Byte(fraction)
  return math.floor(fraction * 255 + 0.5)
end

-- Inline text for a chat line or tooltip: a texture escape (size 0 = as tall as
-- the font) or, for "ignore", a red cross. Empty for an unknown verdict.
function Markers.Icon(verdict, size)
  local look = Markers.Look[verdict]
  if not look then return "" end
  if not look.icon then return RED_CROSS end
  size = size or 0
  if look.tint then
    return string.format("|T%s:%d:%d:0:0:32:32:0:32:0:32:%d:%d:%d|t", look.icon, size, size,
      Byte(look.tint[1]), Byte(look.tint[2]), Byte(look.tint[3]))
  end
  return string.format("|T%s:%d|t", look.icon, size)
end
