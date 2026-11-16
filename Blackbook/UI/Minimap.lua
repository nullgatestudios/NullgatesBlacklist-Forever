-- Blackbook: the minimap button (section 9). Left-click toggles the window,
-- dragging moves it around the minimap edge, and the angle is saved.
local _, ns = ...

local Const = ns.Const
local Events = ns.Events
local Settings = ns.Settings
local Records = ns.Records
local Output = ns.Output

local Minimap_ = {}
ns.Minimap = Minimap_

local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end

-- Offset from the minimap centre of a button at an angle (degrees) on a circle.
function Minimap_.Position(angle, radius)
  local radians = math.rad(angle)
  return math.cos(radians) * radius, math.sin(radians) * radius
end

-- Angle in whole degrees, 0 to 359, of the direction (dx, dy).
function Minimap_.AngleFrom(dx, dy)
  local degrees = math.floor(math.deg(atan2(dy, dx)) + 0.5) % 360
  return degrees
end

local button

local function Place()
  if not button then return end
  local radius = (Minimap:GetWidth() / 2) + 5
  local x, y = Minimap_.Position(Settings.Get("minimapAngle") or 220, radius)
  button:ClearAllPoints()
  button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function ApplyVisibility()
  if not button then return end
  if Settings.Get("showMinimap") then
    Place()
    button:Show()
  else
    button:Hide()
  end
end

-- Follows the cursor while dragging; only runs between drag start and stop.
local function Follow()
  local centerX, centerY = Minimap:GetCenter()
  local cursorX, cursorY = GetCursorPosition()
  local scale = Minimap:GetEffectiveScale()
  local angle = Minimap_.AngleFrom(cursorX / scale - centerX, cursorY / scale - centerY)
  Settings.Set("minimapAngle", angle)
end

local function ShowTooltip(self)
  if not GameTooltip then return end
  GameTooltip:SetOwner(self, "ANCHOR_LEFT")
  GameTooltip:AddLine(Const.ADDON_NAME, 1, 1, 1)
  GameTooltip:AddLine(string.format(Output.Text("MINIMAP_TOOLTIP_COUNT"), #Records.All()), 0.8, 0.8, 0.8)
  GameTooltip:AddLine(Output.Text("MINIMAP_TOOLTIP_HINT"), 0.5, 0.8, 1, true)
  GameTooltip:Show()
end

-- Shows or hides the button and tells the player.
function Minimap_.Toggle()
  local show = not Settings.Get("showMinimap")
  Settings.Set("showMinimap", show)
  Output.Print(Output.Text(show and "MSG_MINIMAP_SHOWN" or "MSG_MINIMAP_HIDDEN"))
end

local registered = false

-- Creates the button. Returns false when the client has no minimap frame.
function Minimap_.Register()
  if registered then return true end
  if not (Minimap and type(CreateFrame) == "function") then return false end
  button = CreateFrame("Button", "BlackbookMinimapButton", Minimap)
  button:SetSize(31, 31)
  button:SetFrameStrata("MEDIUM")
  button:SetFrameLevel(8)
  button:RegisterForClicks("LeftButtonUp")
  button:RegisterForDrag("LeftButton")

  local icon = button:CreateTexture(nil, "BACKGROUND")
  icon:SetSize(20, 20)
  icon:SetPoint("CENTER", button, "CENTER", 0, 1)
  icon:SetTexture(Const.ICON)
  local border = button:CreateTexture(nil, "OVERLAY")
  border:SetSize(53, 53)
  border:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
  border:SetTexture("Interface/Minimap/MiniMap-TrackingBorder")
  button:SetHighlightTexture("Interface/Minimap/UI-Minimap-ZoomButton-Highlight")

  button:SetScript("OnClick", function()
    if ns.Manager then ns.Manager.Toggle() end
  end)
  button:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", Follow)
  end)
  button:SetScript("OnDragStop", function(self)
    self:SetScript("OnUpdate", nil)
  end)
  button:SetScript("OnEnter", ShowTooltip)
  button:SetScript("OnLeave", function()
    if GameTooltip then GameTooltip:Hide() end
  end)

  registered = true
  ApplyVisibility()
  Events:On(Const.Events.SETTINGS_CHANGED, ApplyVisibility)
  return true
end
