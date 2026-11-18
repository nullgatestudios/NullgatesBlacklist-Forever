-- Nullgate's Blacklist: the main window (section 9). It owns the frame and the tab bar;
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

local function Build()
  local name = Widgets.FrameName("NullgateBlacklistManager")
  local window = Widgets.Window(name, 670, 520, Const.DISPLAY_NAME)
  if not window then return nil end

  -- The tab bar under the title.
  for index, tab in ipairs(tabs) do
    tab.button = Widgets.TabButton(window, Text(tab.titleKey), TAB_WIDTH, function() Manager.Show(tab.id) end)
    if tab.button then
      tab.button:SetPoint("TOPLEFT", window, "TOPLEFT", 14 + (index - 1) * (TAB_WIDTH + 4), -32)
    end
  end

  if UISpecialFrames then tinsert(UISpecialFrames, name) end
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
    if tab.button then tab.button:SetActive(tab == target) end
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

-- Throws the window away and, if it was open, opens a fresh one on the same tab.
-- Used when the language changes, so every text is rebuilt in the new language.
function Manager.Reset()
  local wasShown = frame and frame:IsShown()
  local id = activeId
  if frame then frame:Hide() end
  frame = nil
  for _, tab in ipairs(tabs) do tab.button, tab.frame, tab.ui = nil, nil, nil end
  if wasShown then Manager.Show(id) end
end
ns.Locale.OnChange(Manager.Reset)

-- Keep an open window current. Nothing runs while it is closed.
for _, eventName in pairs(Const.Events) do
  Events:On(eventName, Manager.Refresh)
end
