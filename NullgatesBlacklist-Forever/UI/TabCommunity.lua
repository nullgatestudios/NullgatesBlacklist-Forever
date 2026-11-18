-- Nullgate's Blacklist: the "Community" tab (sections 8.9 and 9): the disclosure the
-- player must confirm, the send and receive switches for friends and guild, the
-- reasons that may be shared, a preview of what would be sent, and "revoke and
-- delete". The global channel has its own row and its own confirmation, and is
-- kept apart from friends and guild.
-- Widgets are placed from the top by one running offset so nothing overlaps.
local _, ns = ...

local Const = ns.Const
local Consent = ns.Consent
local Settings = ns.Settings
local Aggregate = ns.Aggregate
local Net = ns.Net
local Output = ns.Output
local Widgets = ns.Widgets

local Text, Print = Output.Text, Output.Print

local TabCommunity = {}
ns.TabCommunity = TabCommunity

local POPUP = "NULLGATE_BLACKLIST_CONFIRM_REVOKE"
local FULL_WIDTH = 630

-- The sources that can be switched on now, in display order.
local SOURCES = { "friends", "guild", "global" }
local GLOBAL_POPUP = "NULLGATE_BLACKLIST_CONFIRM_GLOBAL"

local function LabelSummary(selection)
  local count = 0
  for _ in pairs(selection) do count = count + 1 end
  if count == 0 then return Text("EDITOR_LABELS_NONE") end
  return string.format(Text("EDITOR_LABELS_COUNT"), count)
end

local function Revoke()
  Consent.Revoke()
  Print(Text("COMM_REVOKED"))
end

-- The global channel is public, so it asks once with a notice of its own before a
-- switch can be turned on. run() is what to do when the player agrees; without a
-- popup system nothing is switched on.
local function AskGlobal(run)
  if type(StaticPopupDialogs) ~= "table" or type(StaticPopup_Show) ~= "function" then return end
  StaticPopupDialogs[GLOBAL_POPUP] = {
    text = "%s",
    button1 = Text("COMM_CONFIRM"),
    button2 = Text("COMM_REVOKE_NO"),
    OnAccept = run,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
  }
  StaticPopup_Show(GLOBAL_POPUP, Text("GLOBAL_NOTICE"))
end

-- Asks before revoking; without a popup system it just revokes.
local function ConfirmRevoke()
  if type(StaticPopupDialogs) ~= "table" or type(StaticPopup_Show) ~= "function" then
    Revoke()
    return
  end
  StaticPopupDialogs[POPUP] = {
    text = "%s",
    button1 = Text("COMM_REVOKE_YES"),
    button2 = Text("COMM_REVOKE_NO"),
    OnAccept = Revoke,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
  }
  StaticPopup_Show(POPUP, Text("COMM_REVOKE_CONFIRM"))
end

local function Build(content)
  local state = { switches = {} }
  local y = 0
  local function Place(widget, x, height)
    widget:SetPoint("TOPLEFT", content, "TOPLEFT", x, -y)
    y = y + height
  end

  -- Controls first, so a missing template fails before anything is placed.
  state.confirm = Widgets.Button(content, Text("COMM_CONFIRM"), 220, function()
    Consent.Confirm()
  end)
  for _, source in ipairs(SOURCES) do
    for _, direction in ipairs({ "send", "receive" }) do
      local check = Widgets.Checkbox(content, Text(direction == "send" and "COMM_SEND" or "COMM_RECEIVE"),
        function(self)
          local wanted = self:GetChecked() and true or false
          if wanted and source == "global" and not Consent.GlobalActive() then
            -- First time: show the notice; the switch goes on only if it is accepted.
            self:SetChecked(false)
            AskGlobal(function()
              Consent.ConfirmGlobal()
              Consent.SetToggle(source, direction, true)
            end)
            return
          end
          if not Consent.SetToggle(source, direction, wanted) then self:SetChecked(false) end
        end)
      if not check then return nil end
      state.switches[#state.switches + 1] = { source = source, direction = direction, check = check }
    end
  end
  local items = {}
  for _, entry in ipairs(Const.Labels) do
    items[#items + 1] = { id = entry.id, text = Text(Const.LabelLocaleKey(entry.id)) }
  end
  state.picker = Widgets.MultiSelect(content, items, function()
    Settings.Set("community.shareLabels", state.picker:Get())
  end, { summary = LabelSummary, width = 220 })
  state.preview = Widgets.Button(content, Text("COMM_PREVIEW"), 200, function()
    local lines = {}
    for _, item in ipairs(Net.Preview()) do
      lines[#lines + 1] = string.format(Text("COMM_PREVIEW_LINE"), item.hash,
        Output.LabelText(item.labels), item.day, item.token)
    end
    state.previewText = #lines > 0 and table.concat(lines, "\n") or Text("COMM_PREVIEW_EMPTY")
    state.previewBox.edit:SetText(state.previewText)
  end)
  state.revoke = Widgets.Button(content, Text("COMM_REVOKE"), 160, ConfirmRevoke)
  state.previewBox = Widgets.CodeBox(content, FULL_WIDTH, 78, 20000)
  if not (state.confirm and state.picker and state.preview and state.revoke and state.previewBox) then
    return nil
  end
  -- The preview box shows text only; typing in it changes nothing.
  state.previewText = ""
  state.previewBox.edit:SetScript("OnTextChanged", function(self, byUser)
    if byUser and self:GetText() ~= state.previewText then self:SetText(state.previewText) end
  end)

  -- Disclosure and confirmation.
  Place(Widgets.Label(content, Text("COMM_TITLE")), 4, 22)
  local disclosure = Widgets.Label(content, Text("COMM_DISCLOSURE"), "GameFontHighlightSmall")
  disclosure:SetWidth(FULL_WIDTH)
  disclosure:SetJustifyH("LEFT")
  disclosure:SetJustifyV("TOP")
  Place(disclosure, 4, 108)
  state.confirm:SetPoint("TOPLEFT", content, "TOPLEFT", 4, -y)
  state.consentStatus = Widgets.Label(content, "", "GameFontHighlightSmall")
  state.consentStatus:SetPoint("LEFT", state.confirm, "RIGHT", 12, 0)
  y = y + 30

  -- One row per source: send and receive.
  for index, source in ipairs(SOURCES) do
    local name = Widgets.Label(content, Text("SOURCE_" .. string.upper(source)), "GameFontNormal")
    name:SetPoint("TOPLEFT", content, "TOPLEFT", 4, -(y + 6))
    state.switches[index * 2 - 1].check:SetPoint("TOPLEFT", content, "TOPLEFT", 110, -y)
    state.switches[index * 2].check:SetPoint("TOPLEFT", content, "TOPLEFT", 340, -y)
    y = y + 28
  end
  local note = Widgets.Label(content, Text("COMM_GLOBAL_NOTE"), "GameFontDisableSmall")
  note:SetPoint("TOPLEFT", content, "TOPLEFT", 4, -(y + 2))
  y = y + 20

  -- Reasons, preview and revoke.
  local labelsLabel = Widgets.Label(content, Text("COMM_LABELS"), "GameFontHighlightSmall")
  labelsLabel:SetPoint("TOPLEFT", content, "TOPLEFT", 4, -(y + 6))
  Place(state.picker.frame, 200, state.picker.height + 6)
  state.preview:SetPoint("TOPLEFT", content, "TOPLEFT", 4, -y)
  state.revoke:SetPoint("TOPLEFT", content, "TOPLEFT", FULL_WIDTH - 160, -y)
  y = y + 28
  Place(state.previewBox, 0, 84)
  state.status = Widgets.Label(content, "", "GameFontDisableSmall")
  state.status:SetPoint("TOPLEFT", content, "TOPLEFT", 4, -y)

  state.picker:Set(Settings.Get("community.shareLabels") or {})

  -- Keeps the controls in step with the saved state. It never touches the
  -- preview text, so a refresh cannot wipe what the player is reading.
  local function Refresh()
    local active = Consent.Active()
    Widgets.SetEnabled(state.confirm, not active)
    state.consentStatus:SetText(Text(active and "COMM_CONFIRMED" or "COMM_NOT_CONFIRMED"))
    for _, switch in ipairs(state.switches) do
      switch.check:SetChecked(Consent.Allows(switch.source, switch.direction))
      -- The global switches stay clickable: their first click shows their own notice.
      Widgets.SetEnabled(switch.check, active or switch.source == "global")
    end
    local tokens, targets = Aggregate.Counts()
    state.status:SetText(string.format(Text("COMM_STATUS"), tokens, targets, Net.PendingCount()))
  end

  return { Refresh = Refresh, state = state }
end

ns.Manager.RegisterTab("community", "TAB_COMMUNITY", Build)
