-- Blackbook: the "Rules" tab (sections 8.5, 8.8 and 9): what community reports
-- mean for you. Reports only add a notice until a rule says more. Rules are per
-- source, so friends and guild are never mixed with each other or with global.
-- Below the rules are the flags you hid with "This flag is wrong".
local _, ns = ...

local Const = ns.Const
local Rules = ns.Rules
local Output = ns.Output
local Widgets = ns.Widgets

local Text, Escape = Output.Text, Output.Escape

local TabRules = {}
ns.TabRules = TabRules

local POPUP = "BLACKBOOK_CONFIRM_RULE"
local ROW_HEIGHT = 22
local OK_COLOR, ERROR_COLOR = { 0.5, 1, 0.5 }, { 1, 0.45, 0.45 }

local pendingRules -- the rules waiting for the player's confirmation

local function RuleText(rule)
  return string.format(Text("RULE_TEXT"), Text(Const.LabelLocaleKey(rule.label)),
    Text("SOURCE_" .. string.upper(rule.source)), rule.minTier,
    Text("VERDICT_" .. string.upper(rule.verdict)))
end

-- A rule that ignores players needs an explicit confirmation (section 8.5).
local function Confirm(run)
  if type(StaticPopupDialogs) ~= "table" or type(StaticPopup_Show) ~= "function" then
    run()
    return
  end
  pendingRules = run
  StaticPopupDialogs[POPUP] = {
    text = "%s",
    button1 = Text("RULES_CONFIRM_YES"),
    button2 = Text("RULES_CONFIRM_NO"),
    OnAccept = function()
      local action = pendingRules
      pendingRules = nil
      if action then action() end
    end,
    OnCancel = function() pendingRules = nil end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
  }
  StaticPopup_Show(POPUP, Text("RULES_IGNORE_CONFIRM"))
end

local function Build(content)
  local state = {}
  local y = 0
  local function Place(widget, x, height)
    widget:SetPoint("TOPLEFT", content, "TOPLEFT", x, -y)
    y = y + height
  end
  local function Status(message, ok)
    local color = ok and OK_COLOR or ERROR_COLOR
    state.status:SetTextColor(color[1], color[2], color[3])
    state.status:SetText(message)
  end

  local function SetupRule(row, entry)
    if not row.built then
      row.built = true
      row:RegisterForClicks("LeftButtonUp")
      local highlight = row:CreateTexture(nil, "HIGHLIGHT")
      highlight:SetAllPoints(row)
      highlight:SetColorTexture(1, 1, 1, 0.1)
      row.label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
      row.label:SetPoint("LEFT", row, "LEFT", 6, 0)
      row.label:SetWidth(600)
      row.label:SetJustifyH("LEFT")
      row.label:SetWordWrap(false)
      row:SetScript("OnClick", function(self)
        if self.entry and IsShiftKeyDown and IsShiftKeyDown() then Rules.Remove(self.entry.index) end
      end)
      row:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(Text("RULES_HINT"), 0.5, 0.8, 1)
        GameTooltip:Show()
      end)
      row:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
      end)
    end
    row.entry = entry
    row.label:SetText(Escape(RuleText(entry.rule)))
  end

  local function SetupHidden(row, entry)
    if not row.built then
      row.built = true
      row:RegisterForClicks("LeftButtonUp")
      local highlight = row:CreateTexture(nil, "HIGHLIGHT")
      highlight:SetAllPoints(row)
      highlight:SetColorTexture(1, 1, 1, 0.1)
      row.label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
      row.label:SetPoint("LEFT", row, "LEFT", 6, 0)
      row.label:SetWidth(600)
      row.label:SetJustifyH("LEFT")
      row.label:SetWordWrap(false)
      row:SetScript("OnClick", function(self)
        if self.entry then Rules.Unhide(self.entry.hash) end
      end)
      row:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(Text("HIDDEN_HINT"), 0.5, 0.8, 1)
        GameTooltip:Show()
      end)
      row:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
      end)
    end
    row.entry = entry
    row.label:SetText(Escape(entry.name))
  end

  -- Controls first, so a missing template fails before anything is placed.
  state.rulesList = Widgets.List(content, ROW_HEIGHT, SetupRule)
  state.hiddenList = Widgets.List(content, ROW_HEIGHT, SetupHidden)
  local items = {}
  for _, entry in ipairs(Const.Labels) do
    items[#items + 1] = { id = entry.id, text = Text(Const.LabelLocaleKey(entry.id)) }
  end
  state.labels = Widgets.MultiSelect(content, items, nil, { width = 220,
    summary = function(selection)
      local count = 0
      for _ in pairs(selection) do count = count + 1 end
      if count == 0 then return Text("EDITOR_LABELS_NONE") end
      return string.format(Text("EDITOR_LABELS_COUNT"), count)
    end })
  state.source = Widgets.RadioGroup(content, {
    { value = "friends", text = Text("SOURCE_FRIENDS") },
    { value = "guild", text = Text("SOURCE_GUILD") },
  })
  state.tier = Widgets.RadioGroup(content, {
    { value = 1, text = "1" }, { value = 2, text = "2" },
    { value = 3, text = "3" }, { value = 4, text = "4" },
  })
  state.verdict = Widgets.RadioGroup(content, {
    { value = "warn", text = Text("VERDICT_WARN") },
    { value = "ignore", text = Text("VERDICT_IGNORE") },
  })
  state.add = Widgets.Button(content, Text("RULES_ADD_BUTTON"), 140, function()
    local selected = state.labels:Get()
    local created = {}
    for _, entry in ipairs(Const.Labels) do
      if selected[entry.id] then
        created[#created + 1] = { label = entry.id, source = state.source:GetValue(),
          minTier = state.tier:GetValue(), verdict = state.verdict:GetValue() }
      end
    end
    if #created == 0 then
      Status(Text("RULES_PICK_LABEL"), false)
      return
    end
    local function Create()
      for _, rule in ipairs(created) do
        local ok, err = Rules.Add(rule)
        if not ok then
          Status(Text(err), false)
          return
        end
      end
      Status(Text("RULES_ADDED"), true)
    end
    if state.verdict:GetValue() == "ignore" then Confirm(Create) else Create() end
  end, "primary")
  if not (state.rulesList and state.hiddenList and state.labels and state.source and state.tier
    and state.verdict and state.add) then
    return nil
  end
  state.status = Widgets.Label(content, "", "GameFontHighlightSmall")
  state.none = Widgets.Label(content, Text("RULES_NONE"), "GameFontDisableSmall")
  state.hiddenNone = Widgets.Label(content, Text("HIDDEN_NONE"), "GameFontDisableSmall")

  -- Rules list.
  Place(Widgets.Label(content, Text("RULES_TITLE")), 4, 22)
  state.rulesList.frame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
  state.rulesList.frame:SetSize(630, 110)
  state.none:SetPoint("TOPLEFT", content, "TOPLEFT", 6, -(y + 6))
  y = y + 116

  -- New rule.
  Place(Widgets.Label(content, Text("RULES_NEW")), 4, 24)
  local labelsLabel = Widgets.Label(content, Text("RULES_LABELS"), "GameFontHighlightSmall")
  labelsLabel:SetPoint("TOPLEFT", content, "TOPLEFT", 4, -(y + 6))
  Place(state.labels.frame, 90, state.labels.height + 6)
  local sourceLabel = Widgets.Label(content, Text("RULES_SOURCE"), "GameFontHighlightSmall")
  sourceLabel:SetPoint("TOPLEFT", content, "TOPLEFT", 4, -(y + 6))
  Place(state.source.buttons[1].button, 86, 28)
  state.source:Chain(110)
  local tierLabel = Widgets.Label(content, Text("RULES_TIER"), "GameFontHighlightSmall")
  tierLabel:SetPoint("TOPLEFT", content, "TOPLEFT", 4, -(y + 6))
  Place(state.tier.buttons[1].button, 86, 28)
  state.tier:Chain(60)
  local verdictLabel = Widgets.Label(content, Text("RULES_VERDICT"), "GameFontHighlightSmall")
  verdictLabel:SetPoint("TOPLEFT", content, "TOPLEFT", 4, -(y + 6))
  Place(state.verdict.buttons[1].button, 86, 28)
  state.verdict:Chain(110)
  state.add:SetPoint("TOPLEFT", content, "TOPLEFT", 4, -y)
  state.status:SetPoint("LEFT", state.add, "RIGHT", 12, 0)
  y = y + 32

  -- Hidden flags.
  Place(Widgets.Label(content, Text("HIDDEN_TITLE")), 4, 22)
  state.hiddenList.frame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
  state.hiddenList.frame:SetSize(630, 66)
  state.hiddenNone:SetPoint("TOPLEFT", content, "TOPLEFT", 6, -(y + 6))

  state.source:SetValue("guild")
  state.tier:SetValue(2)
  state.verdict:SetValue("warn")
  state.labels:Set({})

  -- Redraws the two lists. The new-rule controls are never touched here, so a
  -- refresh cannot undo what the player is choosing.
  local function Refresh()
    local entries = {}
    for index, rule in ipairs(Rules.List()) do entries[#entries + 1] = { index = index, rule = rule } end
    state.rulesList:SetData(entries)
    if #entries == 0 then state.none:Show() else state.none:Hide() end
    local hidden = Rules.HiddenList()
    state.hiddenList:SetData(hidden)
    if #hidden == 0 then state.hiddenNone:Show() else state.hiddenNone:Hide() end
  end

  return { Refresh = Refresh, state = state }
end

ns.Manager.RegisterTab("rules", "TAB_RULES", Build)
