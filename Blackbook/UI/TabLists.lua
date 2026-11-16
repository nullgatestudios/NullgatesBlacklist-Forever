-- Blackbook: the "Lists" tab (section 9): the imported lists, and for the
-- chosen one what each reason means (notice, warn or ignore). Removing a list
-- needs Shift-click.
local _, ns = ...

local Const = ns.Const
local Subscriptions = ns.Subscriptions
local Output = ns.Output
local Widgets = ns.Widgets

local Text, Print, Escape = Output.Text, Output.Print, Output.Escape

local TabLists = {}
ns.TabLists = TabLists

local ROW_HEIGHT = 24
local LIST_WIDTH = 230
local RIGHT = 246

local function Build(content)
  local state = {}
  local function Refresh() if state.refresh then state.refresh() end end

  local function SetupRow(row, subscription)
    if not row.built then
      row.built = true
      row:RegisterForClicks("LeftButtonUp")
      local highlight = row:CreateTexture(nil, "HIGHLIGHT")
      highlight:SetAllPoints(row)
      highlight:SetColorTexture(1, 1, 1, 0.1)
      row.selection = row:CreateTexture(nil, "BACKGROUND")
      row.selection:SetAllPoints(row)
      row.selection:SetColorTexture(0.2, 0.5, 1, 0.3)
      row.name = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
      row.name:SetPoint("LEFT", row, "LEFT", 6, 0)
      row.name:SetWidth(LIST_WIDTH - 70)
      row.name:SetJustifyH("LEFT")
      row.name:SetWordWrap(false)
      row.count = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
      row.count:SetPoint("RIGHT", row, "RIGHT", -22, 0)
      row:SetScript("OnClick", function(self)
        if self.subscription then
          state.selected = self.subscription.id
          Refresh()
        end
      end)
      row:SetScript("OnEnter", function(self)
        if not self.subscription or not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(Escape(self.subscription.name), 1, 1, 1)
        GameTooltip:AddLine(Escape(self.subscription.author), 0.8, 0.8, 0.8)
        GameTooltip:AddLine(Text("LISTS_ROW_HINT"), 0.5, 0.8, 1)
        GameTooltip:Show()
      end)
      row:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
      end)
    end
    row.subscription = subscription
    row.name:SetText(Escape(subscription.name))
    row.count:SetText(tostring(subscription.count or 0))
    if subscription.id == state.selected then row.selection:Show() else row.selection:Hide() end
  end

  state.list = Widgets.List(content, ROW_HEIGHT, SetupRow)
  if not state.list then return nil end
  state.list.frame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -4)
  state.list.frame:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 0, 4)
  state.list.frame:SetWidth(LIST_WIDTH)

  state.empty = Widgets.Label(content, Text("LISTS_EMPTY"), "GameFontHighlight")
  state.empty:SetPoint("TOPLEFT", content, "TOPLEFT", RIGHT, -8)
  state.empty:SetWidth(380)
  state.empty:SetJustifyH("LEFT")

  state.details = Widgets.Label(content, "", "GameFontHighlight")
  state.details:SetPoint("TOPLEFT", content, "TOPLEFT", RIGHT, -8)
  state.details:SetWidth(390)
  state.details:SetJustifyH("LEFT")

  local rulesTitle = Widgets.Label(content, Text("LISTS_RULES"))
  rulesTitle:SetPoint("TOPLEFT", content, "TOPLEFT", RIGHT, -64)
  state.rulesTitle = rulesTitle

  -- One row per reason: its name and a notice / warn / ignore choice.
  state.groups = {}
  state.rows = { rulesTitle }
  local y = 90
  for _, entry in ipairs(Const.Labels) do
    local id = entry.id
    local name = Widgets.Label(content, Text(Const.LabelLocaleKey(id)), "GameFontHighlightSmall")
    name:SetPoint("TOPLEFT", content, "TOPLEFT", RIGHT, -(y + 6))
    name:SetWidth(168)
    name:SetJustifyH("LEFT")
    name:SetWordWrap(false)
    local group = Widgets.RadioGroup(content, {
      { value = "notice", text = Text("VERDICT_NOTICE") },
      { value = "warn", text = Text("VERDICT_WARN") },
      { value = "ignore", text = Text("VERDICT_IGNORE") },
    }, function(value)
      if state.selected then Subscriptions.SetRule(state.selected, id, value) end
    end)
    if not group then return nil end
    group.buttons[1].button:SetPoint("TOPLEFT", content, "TOPLEFT", RIGHT + 176, -y)
    group:Chain(72)
    state.groups[id] = group
    state.rows[#state.rows + 1] = name
    y = y + 28
  end

  state.remove = Widgets.Button(content, Text("LISTS_REMOVE"), 140, function()
    local subscription = state.selected and Subscriptions.Get(state.selected)
    if not subscription then return end
    if IsShiftKeyDown and IsShiftKeyDown() then
      Subscriptions.Remove(subscription.id)
      Print(string.format(Text("LISTS_REMOVED"), Escape(subscription.name)))
    else
      Print(Text("LISTS_REMOVE_HINT"))
    end
  end, "danger")
  if not state.remove then return nil end
  state.remove:SetPoint("TOPLEFT", content, "TOPLEFT", RIGHT, -(y + 10))
  local hint = Widgets.Label(content, Text("LISTS_REMOVE_HINT"), "GameFontDisableSmall")
  hint:SetPoint("LEFT", state.remove, "RIGHT", 10, 0)

  function state.refresh()
    local subscriptions = Subscriptions.All()
    local selected = state.selected and Subscriptions.Get(state.selected)
    if not selected then
      selected = subscriptions[1]
      state.selected = selected and selected.id or nil
    end
    state.list:SetData(subscriptions)

    local any = selected ~= nil
    if any then state.empty:Hide() else state.empty:Show() end
    if any then state.details:Show() else state.details:Hide() end
    for _, widget in ipairs(state.rows) do
      if any then widget:Show() else widget:Hide() end
    end
    if any then
      state.details:SetText(string.format(Text("LISTS_DETAILS"), Escape(selected.name),
        Escape(selected.author), selected.count or 0, Output.Date(selected.imported) or Text("DATE_UNKNOWN")))
    end
    for id, group in pairs(state.groups) do
      group:SetValue(any and Subscriptions.Rule(selected.id, id) or nil)
      for _, entry in ipairs(group.buttons) do
        if any then entry.button:Show() else entry.button:Hide() end
      end
    end
    if any then state.remove:Show() else state.remove:Hide() end
    if any then hint:Show() else hint:Hide() end
  end

  return { Refresh = state.refresh, state = state }
end

ns.Manager.RegisterTab("lists", "TAB_LISTS", Build)
