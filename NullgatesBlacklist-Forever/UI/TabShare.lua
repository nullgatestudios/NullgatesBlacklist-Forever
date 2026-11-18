-- Nullgate's Blacklist: the "Share" tab (section 9): export the own list as a code and
-- import a pasted code after a confirmation. Sharing with friends and guild is
-- automatic and lives on the Community tab.
-- Widgets are placed from the top by one running offset so nothing overlaps.
local _, ns = ...

local Const = ns.Const
local Codec = ns.Codec
local Settings = ns.Settings
local Subscriptions = ns.Subscriptions
local Output = ns.Output
local Widgets = ns.Widgets

local Text, Print, Escape = Output.Text, Output.Print, Output.Escape

local TabShare = {}
ns.TabShare = TabShare

local POPUP = "NULLGATE_BLACKLIST_CONFIRM_IMPORT"
local FULL_WIDTH = 630
local OK_COLOR, ERROR_COLOR = { 0.5, 1, 0.5 }, { 1, 0.45, 0.45 }

local pendingImport -- function to run when the player confirms the popup

local function LabelSummary(selection)
  local count = 0
  for _ in pairs(selection) do count = count + 1 end
  if count == 0 then return Text("EDITOR_LABELS_NONE") end
  return string.format(Text("EDITOR_LABELS_COUNT"), count)
end

-- Asks before importing: the list name, its author, the size and the date.
-- Without a popup system the import just goes ahead.
local function Confirm(list, run)
  if type(StaticPopupDialogs) ~= "table" or type(StaticPopup_Show) ~= "function" then
    run()
    return
  end
  pendingImport = run
  StaticPopupDialogs[POPUP] = {
    text = "%s\n%s",
    button1 = Text("IMPORT_CONFIRM_YES"),
    button2 = Text("IMPORT_CONFIRM_NO"),
    OnAccept = function()
      local action = pendingImport
      pendingImport = nil
      if action then action() end
    end,
    OnCancel = function() pendingImport = nil end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
  }
  StaticPopup_Show(POPUP,
    string.format(Text("IMPORT_CONFIRM_LIST"), Escape(list.name), Escape(list.author)),
    string.format(Text("IMPORT_CONFIRM_INFO"), list.count, Output.Date(list.exported) or Text("DATE_UNKNOWN")))
end

local function Build(content)
  local state = { code = "" }
  local y = 0
  local function Place(widget, x, height)
    widget:SetPoint("TOPLEFT", content, "TOPLEFT", x, -y)
    y = y + height
  end
  local function Header(key)
    Place(Widgets.Label(content, Text(key)), 4, 24)
  end
  local function Status(label, message, ok)
    local color = ok and OK_COLOR or ERROR_COLOR
    label:SetTextColor(color[1], color[2], color[3])
    label:SetText(message)
  end

  -- Controls first, so a missing template fails before anything is placed.
  state.nameBox = Widgets.InputBox(content, 300, Const.Limits.listName)
  local items = {}
  for _, entry in ipairs(Const.Labels) do
    items[#items + 1] = { id = entry.id, text = Text(Const.LabelLocaleKey(entry.id)) }
  end
  state.picker = Widgets.MultiSelect(content, items, function()
    Settings.Set("export.labels", state.picker:Get())
  end, { summary = LabelSummary, width = 220 })
  state.comments = Widgets.Checkbox(content, Text("SHARE_COMMENTS"), function(self)
    Settings.Set("export.comments", self:GetChecked() and true or false)
  end)
  state.codeBox = Widgets.CodeBox(content, FULL_WIDTH, 64, Const.Limits.codeBytes)
  state.pasteBox = Widgets.CodeBox(content, FULL_WIDTH, 64, Const.Limits.codeBytes)
  if not (state.nameBox and state.picker and state.comments and state.codeBox
    and state.pasteBox) then
    return nil
  end

  state.exportStatus = Widgets.Label(content, "", "GameFontHighlightSmall")
  state.importStatus = Widgets.Label(content, "", "GameFontHighlightSmall")

  state.exportButton = Widgets.Button(content, Text("SHARE_EXPORT_BUTTON"), 140, function()
    local name = state.nameBox:GetText()
    Settings.Set("export.name", (name and name ~= "") and name or nil)
    local code, count = Codec.ExportOwn()
    state.code = count > 0 and code or ""
    state.codeBox.edit:SetText(state.code)
    if count == 0 then
      Status(state.exportStatus, Text("ERR_EXPORT_EMPTY"), false)
      return
    end
    Status(state.exportStatus, string.format(Text("SHARE_EXPORT_DONE"), count), true)
    state.codeBox.edit:SetFocus()
    state.codeBox.edit:HighlightText()
  end)
  state.importButton = Widgets.Button(content, Text("SHARE_IMPORT_BUTTON"), 100, function()
    local list, err, detail = Codec.Decode(state.pasteBox.edit:GetText())
    if not list then
      Status(state.importStatus, Output.Error(err, detail), false)
      return
    end
    if list.id == Settings.Get("export.id") then
      Status(state.importStatus, Text("ERR_OWN_LIST"), false)
      return
    end
    Confirm(list, function()
      local subscription, replaced = Subscriptions.Import(list)
      if not subscription then
        Status(state.importStatus, Text(replaced), false)
        return
      end
      state.pasteBox.edit:SetText("")
      Status(state.importStatus, Subscriptions.Summary(subscription, replaced), true)
    end)
  end)
  state.clearButton = Widgets.Button(content, Text("SHARE_CLEAR"), 100, function()
    state.pasteBox.edit:SetText("")
    state.importStatus:SetText("")
  end)
  if not (state.exportButton and state.importButton and state.clearButton) then
    return nil
  end

  -- The code box mirrors the last export and cannot be edited by typing.
  state.codeBox.edit:SetScript("OnTextChanged", function(self, byUser)
    if byUser and self:GetText() ~= state.code then self:SetText(state.code) end
  end)
  state.codeBox.edit:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)

  -- Export.
  Header("SHARE_EXPORT")
  local nameLabel = Widgets.Label(content, Text("SHARE_NAME"), "GameFontHighlightSmall")
  nameLabel:SetPoint("TOPLEFT", content, "TOPLEFT", 4, -(y + 5))
  Place(state.nameBox, 130, 30)
  local labelsLabel = Widgets.Label(content, Text("SHARE_LABELS"), "GameFontHighlightSmall")
  labelsLabel:SetPoint("TOPLEFT", content, "TOPLEFT", 4, -(y + 6))
  Place(state.picker.frame, 126, state.picker.height + 6)
  Place(state.comments, 0, 28)
  state.exportButton:SetPoint("TOPLEFT", content, "TOPLEFT", 4, -y)
  state.exportStatus:SetPoint("LEFT", state.exportButton, "RIGHT", 12, 0)
  y = y + 30
  Place(state.codeBox, 0, 74)

  -- Import.
  Header("SHARE_IMPORT")
  Place(state.pasteBox, 0, 68)
  state.importButton:SetPoint("TOPLEFT", content, "TOPLEFT", 4, -y)
  state.clearButton:SetPoint("LEFT", state.importButton, "RIGHT", 8, 0)
  state.importStatus:SetPoint("LEFT", state.clearButton, "RIGHT", 12, 0)
  y = y + 34

  state.height = y

  -- Show the saved export settings once; typing is never overwritten.
  state.nameBox:SetText(Settings.Get("export.name") or "")
  state.picker:Set(Settings.Get("export.labels") or {})
  state.comments:SetChecked(Settings.Get("export.comments") ~= false)

  return { state = state }
end

ns.Manager.RegisterTab("share", "TAB_SHARE", Build)
