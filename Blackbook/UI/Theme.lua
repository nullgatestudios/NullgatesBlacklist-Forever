-- Blackbook: the look (section 9). One place for the colours and fonts of the
-- flat, dark style every window uses: a near-black panel with a 1 pixel border,
-- a gold accent taken from the addon icon, calm grey text and no Blizzard
-- frame art. Only plain textures and font strings are used, so it needs no
-- template that a client might lack.
local _, ns = ...

local Theme = {}
ns.Theme = Theme

Theme.color = {
  window = { 0.065, 0.075, 0.095, 0.97 },
  titlebar = { 0.095, 0.105, 0.13, 1 },
  border = { 0.21, 0.23, 0.29, 1 },
  divider = { 1, 1, 1, 0.07 },
  field = { 0.04, 0.05, 0.07, 1 },
  button = { 0.165, 0.18, 0.225, 1 },
  buttonHover = { 0.22, 0.245, 0.31, 1 },
  buttonDown = { 0.12, 0.13, 0.17, 1 },
  buttonOff = { 0.11, 0.12, 0.15, 1 },
  primary = { 0.96, 0.78, 0.30, 1 },
  primaryHover = { 1, 0.86, 0.46, 1 },
  primaryDown = { 0.78, 0.62, 0.20, 1 },
  primaryText = { 0.09, 0.08, 0.04 },
  danger = { 1, 0.42, 0.42 },
  dangerHover = { 0.36, 0.14, 0.15, 1 },
  accent = { 0.96, 0.78, 0.30 },
  text = { 0.92, 0.93, 0.96 },
  muted = { 0.60, 0.63, 0.70 },
  off = { 0.40, 0.42, 0.47 },
  ok = { 0.45, 0.90, 0.55 },
  rowHover = { 1, 1, 1, 0.08 },
  rowSelected = { 0.96, 0.78, 0.30, 0.18 },
}

-- --- Drawing helpers -------------------------------------------------------------------

local function Unpack(color)
  return color[1], color[2], color[3], color[4] or 1
end
Theme.Unpack = Unpack

-- A solid background behind the whole frame. Returns the texture.
function Theme.Fill(frame, color, layer)
  local texture = frame:CreateTexture(nil, layer or "BACKGROUND")
  texture:SetAllPoints(frame)
  texture:SetColorTexture(Unpack(color))
  return texture
end

-- A 1 pixel border around the frame. Returns { SetColor = function(color) }.
function Theme.Border(frame, color)
  local edges = {}
  local function Edge(point1, point2, horizontal)
    local edge = frame:CreateTexture(nil, "BORDER")
    edge:SetPoint(point1, frame, point1, 0, 0)
    edge:SetPoint(point2, frame, point2, 0, 0)
    if horizontal then edge:SetHeight(1) else edge:SetWidth(1) end
    edge:SetColorTexture(Unpack(color))
    edges[#edges + 1] = edge
  end
  Edge("TOPLEFT", "TOPRIGHT", true)
  Edge("BOTTOMLEFT", "BOTTOMRIGHT", true)
  Edge("TOPLEFT", "BOTTOMLEFT", false)
  Edge("TOPRIGHT", "BOTTOMRIGHT", false)
  return {
    SetColor = function(newColor)
      for _, edge in ipairs(edges) do edge:SetColorTexture(Unpack(newColor)) end
    end,
  }
end

-- --- Fonts ------------------------------------------------------------------------------
-- Our own font objects, so no other addon's text changes. Latin and Cyrillic use
-- the sans-serif face the chat uses; languages written in Chinese, Japanese or
-- Korean keep the client's standard font, which is the one with those glyphs.

local SANS = "Fonts\\ARIALN.TTF"
local NEEDS_CLIENT_FONT = { zh = true, ja = true, ko = true }

-- name -> { object name, size, colour }. Blizzard names are mapped, so the rest
-- of the addon keeps asking for the font it always asked for.
local FONTS = {
  GameFontNormalLarge = { "BlackbookTitle", 18, "accent" },
  GameFontNormal = { "BlackbookHeader", 14, "accent" },
  GameFontHighlight = { "BlackbookText", 13, "text" },
  GameFontHighlightSmall = { "BlackbookSmall", 12, "text" },
  GameFontDisableSmall = { "BlackbookMuted", 12, "muted" },
}

local made = {}

-- Creates or updates the font objects for the current language. Safe to call
-- again; does nothing where the client has no CreateFont.
function Theme.Fonts()
  if type(CreateFont) ~= "function" then return end
  local path = SANS
  local current = ns.Locale and ns.Locale.current
  if current and NEEDS_CLIENT_FONT[current] and STANDARD_TEXT_FONT then path = STANDARD_TEXT_FONT end
  for _, spec in pairs(FONTS) do
    local name, size, colorName = spec[1], spec[2], spec[3]
    local font = made[name]
    if not font then
      font = CreateFont(name)
      made[name] = font
    end
    -- SetFont reports false for a file it cannot load; then the standard font stays.
    local ok, loaded = pcall(font.SetFont, font, path, size, "")
    if not (ok and loaded ~= false) and GameFontNormal and type(font.SetFontObject) == "function" then
      font:SetFontObject(GameFontNormal)
    end
    font:SetTextColor(Unpack(Theme.color[colorName]))
  end
end

-- The font object name to use for a Blizzard font name.
function Theme.Font(name)
  local spec = FONTS[name]
  if spec and type(CreateFont) == "function" then
    if not made[spec[1]] then Theme.Fonts() end
    return spec[1]
  end
  return name
end

if ns.Locale then ns.Locale.OnChange(Theme.Fonts) end
