-- Blackbook: the main window (section 9). It owns the frame and the tab bar;
-- each tab module registers a builder with RegisterTab and fills its own
-- content frame the first time it is shown.
local _, ns = ...

local Const = ns.Const
local Events = ns.Events
local Output = ns.Output
local Widgets = ns.Widgets

local Text, Print = Output.Text, Output.Print

local Manager = {}
ns.Manager = Manager

local TAB_WIDTH = 88 -- seven tabs have to fit the window
local tabs = {}      -- { id =, titleKey =, build =, button =, frame =, ui = }
local frame          -- the window, built on first use
local activeId

local function TabById(id)
  for _, tab in ipairs(tabs) do
    if tab.id == id then return tab end
  end
  return nil
end

-- Registers a tab. build(contentFrame) returns an object with an optional
-- Refresh() method, or nil when the client lacks something the tab needs.
function Manager.RegisterTab(id, titleKey, build)
  tabs[#tabs + 1] = { id = id, titleKey = titleKey, build = build }
end

local function SetTitle(target, title)
  if type(target.SetTitle) == "function" then
    target:SetTitle(title)
  elseif target.TitleContainer and target.TitleContainer.TitleText then
    target.TitleContainer.TitleText:SetText(title)
  end
end

local function Build()
  local window = Widgets.Create("Frame", "BasicFrameTemplateWithInset", UIParent, "BlackbookManager")
  if not window then return nil end
  window:SetSize(670, 520)
  window:SetPoint("CENTER")
  window:SetClampedToScreen(true)
  window:SetFrameStrata("DIALOG") -- above other addons' HUD frames
  window:SetToplevel(true)
  window:SetMovable(true)
  window:EnableMouse(true)
  window:RegisterForDrag("LeftButton")
  window:SetScript("OnDragStart", function(self) self:StartMoving() end)
  window:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
  SetTitle(window, Const.ADDON_NAME)

  for index, tab in ipairs(tabs) do
    tab.button = Widgets.Button(window, Text(tab.titleKey), TAB_WIDTH, function() Manager.Show(tab.id) end)
    if tab.button then
      tab.button:SetPoint("TOPLEFT", window, "TOPLEFT", 14 + (index - 1) * (TAB_WIDTH + 4), -32)
    end
  end

  if UISpecialFrames then tinsert(UISpecialFrames, "BlackbookManager") end
  window:Hide()
  return window
end

-- The content frame of a tab, built on first use.
local function EnsureTab(tab)
  if tab.frame then return end
  tab.frame = Widgets.Create("Frame", nil, frame)
  tab.frame:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -64)
  tab.frame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14, 14)
  tab.ui = tab.build(tab.frame)
  if not tab.ui then
    local notice = Widgets.Label(tab.frame, Text("TAB_UNAVAILABLE"), "GameFontHighlight")
    notice:SetPoint("TOPLEFT", tab.frame, "TOPLEFT", 0, -8)
  end
end

-- Redraws the visible tab. Cheap when the window is closed.
function Manager.Refresh()
  if not frame or not frame:IsShown() then return end
  local tab = TabById(activeId)
  if tab and tab.ui and type(tab.ui.Refresh) == "function" then tab.ui.Refresh() end
end

-- Opens the window on a tab (the first one by default).
function Manager.Show(id)
  if not frame then frame = Build() end
  if not frame then
    Print(Text("MSG_NO_UI"))
    return false
  end
  local target = TabById(id) or TabById(activeId) or tabs[1]
  if not target then return false end
  activeId = target.id
  for _, tab in ipairs(tabs) do
    if tab.frame then tab.frame:Hide() end
    if tab.button then Widgets.SetEnabled(tab.button, tab ~= target) end
  end
  EnsureTab(target)
  target.frame:Show()
  frame:Show()
  Manager.Refresh()
  return true
end

function Manager.Toggle()
  if frame and frame:IsShown() then
    frame:Hide()
  else
    Manager.Show(activeId)
  end
end

-- Keep an open window current. Nothing runs while it is closed.
for _, eventName in pairs(Const.Events) do
  Events:On(eventName, Manager.Refresh)
end
