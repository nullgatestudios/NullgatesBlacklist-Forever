-- Blackbook: ADDON_LOADED bootstrap and slash commands (sections 4.1, 6.5).
-- The editor here is a temporary stub for M1; UI/Editor.lua replaces it in M3.
local addonName, ns = ...

local Const = ns.Const

local Text, Escape, Print = ns.Output.Text, ns.Output.Escape, ns.Output.Print

local function VerdictText(verdict)
  return Text("VERDICT_" .. string.upper(tostring(verdict or "")))
end

-- "auto" follows the client locale; de and en are explicit (section 10).
local function ApplyLanguage()
  local choice = ns.Settings.Get("language")
  if choice ~= "de" and choice ~= "en" then
    local client = "enUS"
    if type(GetLocale) == "function" then client = GetLocale() or client end
    choice = (client == "deDE") and "de" or "en"
  end
  if choice == "de" and ns.L_DE then
    ns.L = ns.L_DE
  end
end

-- Returns a frame using a template, or nil when the client lacks it. The
-- fallback policy of section 2 applies: the addon keeps running and only the
-- affected feature is disabled.
local function NewTemplated(kind, template, parent, name)
  local ok, frame = pcall(CreateFrame, kind, name, parent, template)
  if ok and frame then return frame end
  return nil
end

local function SetCheckText(check, text)
  if type(check.SetText) == "function" then
    check:SetText(text)
    return
  end
  local label = check:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  label:SetPoint("LEFT", check, "RIGHT", 4, 0)
  label:SetText(text)
end

local editor

local function CreateEditor()
  local frame = NewTemplated("Frame", "BasicFrameTemplateWithInset", UIParent, "BlackbookEditor")
  if not frame then return nil end
  local nameBox = NewTemplated("EditBox", "InputBoxTemplate", frame, nil)
  local commentBox = NewTemplated("EditBox", "InputBoxTemplate", frame, nil)
  local saveButton = NewTemplated("Button", "UIPanelButtonTemplate", frame, nil)
  local cancelButton = NewTemplated("Button", "UIPanelButtonTemplate", frame, nil)
  local ignoreCheck = NewTemplated("CheckButton", "UICheckButtonTemplate", frame, nil)
  local warnCheck = NewTemplated("CheckButton", "UICheckButtonTemplate", frame, nil)
  if not (nameBox and commentBox and saveButton and cancelButton and ignoreCheck and warnCheck) then
    frame:Hide()
    return nil
  end

  frame:SetSize(360, 440)
  frame:SetPoint("CENTER")
  frame:SetClampedToScreen(true)
  frame.title = _G["BlackbookEditorTitleText"]
    or (frame.TitleContainer and frame.TitleContainer.TitleText) or nil

  local nameLabel = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  nameLabel:SetPoint("TOPLEFT", 16, -36)
  nameLabel:SetText(Text("EDITOR_NAME"))

  nameBox:SetSize(330, 20)
  nameBox:SetPoint("TOPLEFT", nameLabel, "BOTTOMLEFT", 0, -4)
  nameBox:SetAutoFocus(false)
  nameBox:SetMaxLetters(Const.Limits.name)
  nameBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  nameBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

  local verdictLabel = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  verdictLabel:SetPoint("TOPLEFT", nameBox, "BOTTOMLEFT", 0, -14)
  verdictLabel:SetText(Text("EDITOR_VERDICT"))

  ignoreCheck:SetPoint("TOPLEFT", verdictLabel, "BOTTOMLEFT", 0, -4)
  SetCheckText(ignoreCheck, Text("VERDICT_IGNORE"))

  warnCheck:SetPoint("LEFT", ignoreCheck, "RIGHT", 110, 0)
  SetCheckText(warnCheck, Text("VERDICT_WARN"))

  local labelsLabel = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  labelsLabel:SetPoint("TOPLEFT", ignoreCheck, "BOTTOMLEFT", 0, -14)
  labelsLabel:SetText(Text("EDITOR_LABELS"))

  local labelChecks = {}
  for index, entry in ipairs(Const.Labels) do
    local check = NewTemplated("CheckButton", "UICheckButtonTemplate", frame, nil)
    if not check then
      frame:Hide()
      return nil
    end
    local column = (index - 1) % 2
    local row = math.floor((index - 1) / 2)
    check:SetPoint("TOPLEFT", labelsLabel, "BOTTOMLEFT", column * 165, -4 - row * 24)
    SetCheckText(check, Text(Const.LabelLocaleKey(entry.id)))
    labelChecks[entry.id] = check
  end

  local commentLabel = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  commentLabel:SetPoint("TOPLEFT", labelsLabel, "BOTTOMLEFT", 0, -132)
  commentLabel:SetText(Text("EDITOR_COMMENT"))

  commentBox:SetSize(330, 70)
  commentBox:SetPoint("TOPLEFT", commentLabel, "BOTTOMLEFT", 0, -4)
  commentBox:SetMultiLine(true)
  commentBox:SetAutoFocus(false)
  commentBox:SetMaxLetters(Const.Limits.comment)
  commentBox:SetTextInsets(8, 8, 4, 4)
  commentBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

  saveButton:SetSize(100, 22)
  saveButton:SetPoint("TOPLEFT", commentBox, "BOTTOMLEFT", 60, -14)
  saveButton:SetText(Text("EDITOR_SAVE"))

  cancelButton:SetSize(100, 22)
  cancelButton:SetPoint("LEFT", saveButton, "RIGHT", 12, 0)
  cancelButton:SetText(Text("EDITOR_CANCEL"))
  cancelButton:SetScript("OnClick", function() frame:Hide() end)

  function frame:SetVerdict(verdict)
    self.verdict = verdict
    ignoreCheck:SetChecked(verdict == "ignore")
    warnCheck:SetChecked(verdict == "warn")
  end

  ignoreCheck:SetScript("OnClick", function() frame:SetVerdict("ignore") end)
  warnCheck:SetScript("OnClick", function() frame:SetVerdict("warn") end)

  function frame:Open(name, verdict)
    local record = ns.Records.Get(name)
    if record then
      nameBox:SetText(record.name)
      self:SetVerdict(record.verdict)
      commentBox:SetText(record.comment or "")
      for id, check in pairs(labelChecks) do
        check:SetChecked((record.labels and record.labels[id]) and true or false)
      end
    else
      nameBox:SetText(name)
      self:SetVerdict(verdict or "ignore")
      commentBox:SetText("")
      for _, check in pairs(labelChecks) do
        check:SetChecked(false)
      end
    end
    if self.title then self.title:SetText(Text("EDITOR_TITLE")) end
    self.original = record and record.name or nil
    self:Show()
  end

  saveButton:SetScript("OnClick", function()
    local verdict = frame.verdict == "warn" and "warn" or "ignore"
    local labels = {}
    for id, check in pairs(labelChecks) do
      if check:GetChecked() then labels[id] = true end
    end
    local record, err = ns.Records.Save(nameBox:GetText(), verdict, labels, commentBox:GetText())
    if not record then
      Print(Text(err))
      return
    end
    -- Editing the name field of an existing record moves it instead of
    -- leaving the old entry behind.
    if frame.original and not ns.Identity.Same(frame.original, record.name) then
      ns.Records.Remove(frame.original)
    end
    frame.original = record.name
    Print(string.format(Text("MSG_RECORD_SAVED"), Escape(record.name), VerdictText(record.verdict)))
    frame:Hide()
  end)

  if UISpecialFrames then tinsert(UISpecialFrames, "BlackbookEditor") end
  frame:Hide()
  return frame
end

-- Opens the temporary editor with the name prefilled (section 6.5).
local function OpenEditor(name, verdict)
  local normalized = ns.Identity.Normalize(name)
  if not normalized then
    Print(Text("ERR_NAME"))
    return
  end
  if ns.Identity.Same(normalized, ns.Identity.Self()) then
    Print(Text("MSG_SELF"))
    return
  end
  if not editor then
    editor = CreateEditor()
    if not editor then
      Print(Text("MSG_NO_UI"))
      return
    end
  end
  editor:Open(normalized, verdict)
end

local function ListRecords()
  local records = ns.Records.All()
  if #records == 0 then
    Print(Text("MSG_LIST_EMPTY"))
    return
  end
  Print(string.format(Text("MSG_LIST_HEADER"), #records))
  for _, record in ipairs(records) do
    local names = {}
    for _, entry in ipairs(Const.Labels) do
      if record.labels and record.labels[entry.id] then
        names[#names + 1] = Text(Const.LabelLocaleKey(entry.id))
      end
    end
    Print(string.format("%s - %s - %s - %s",
      Escape(record.name), VerdictText(record.verdict),
      Escape(table.concat(names, ", ")), Escape(record.comment)))
  end
end

local function RemoveRecord(name)
  local record = ns.Records.Get(name)
  if not record then
    local display = ns.Identity.Normalize(name) or tostring(name)
    Print(string.format(Text("MSG_RECORD_NOT_FOUND"), Escape(display)))
    return
  end
  local display = record.name
  ns.Records.Remove(name)
  Print(string.format(Text("MSG_RECORD_REMOVED"), Escape(display)))
end

local function ToggleManager()
  if ns.Manager and type(ns.Manager.Toggle) == "function" then
    ns.Manager.Toggle()
  else
    Print(Text("MSG_NO_MANAGER"))
  end
end

local function SetLanguage(value)
  local choice = string.lower(value or "")
  if choice ~= "de" and choice ~= "en" and choice ~= "auto" then
    Print(Text("MSG_LANG_INVALID"))
    return
  end
  ns.Settings.Set("language", choice)
  Print(string.format(Text("MSG_LANG_SET"), Escape(choice)))
end

-- The version lives only in the TOC (section 15.1); read it from there.
local function ShowVersion()
  local getMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
  local version
  if type(getMeta) == "function" then
    local ok, value = pcall(getMeta, addonName, "Version")
    if ok then version = value end
  end
  Print(string.format(Text("MSG_VERSION"), Escape(version or "?")))
end

local function ShowHelp()
  local keys = {
    "HELP_HEADER", "HELP_TOGGLE", "HELP_LIST", "HELP_IGNORE", "HELP_WARN",
    "HELP_REMOVE", "HELP_SETUP", "HELP_MINIMAP", "HELP_LANG", "HELP_VERSION",
    "HELP_HELP",
  }
  for _, key in ipairs(keys) do
    Print(Text(key))
  end
end

local function HandleSlash(input)
  local command, rest = string.match(input or "", "^%s*(%S*)%s*(.-)%s*$")
  command = string.lower(command or "")
  if command == "" then
    ToggleManager()
  elseif command == "list" then
    ListRecords()
  elseif command == "ignore" or command == "warn" then
    if rest == "" then
      Print(string.format(Text("MSG_NEED_NAME"), command))
    else
      OpenEditor(rest, command)
    end
  elseif command == "remove" then
    if rest == "" then
      Print(string.format(Text("MSG_NEED_NAME"), command))
    else
      RemoveRecord(rest)
    end
  elseif command == "setup" then
    Print(string.format(Text("MSG_NOT_AVAILABLE"), Text("CMD_SETUP")))
  elseif command == "minimap" then
    Print(string.format(Text("MSG_NOT_AVAILABLE"), Text("CMD_MINIMAP")))
  elseif command == "lang" then
    SetLanguage(rest)
  elseif command == "version" then
    ShowVersion()
  elseif command == "help" then
    ShowHelp()
  else
    Print(string.format(Text("MSG_UNKNOWN_COMMAND"), Escape(command)))
  end
end

SLASH_BLACKBOOK1 = Const.SLASH_BLACKBOOK
SLASH_BLACKBOOK2 = Const.SLASH_BLACKBOOK_SHORT
SlashCmdList["BLACKBOOK"] = HandleSlash

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(_, event, name)
  if event ~= "ADDON_LOADED" or name ~= addonName then return end
  local _, state = ns.Settings.Init()
  ApplyLanguage()
  ns.Chat.Register()
  ns.Requests.Register()
  if state == "newer" then Print(Text("MSG_DB_NEWER")) end
  Print(Text("MSG_LOADED"))
end)
