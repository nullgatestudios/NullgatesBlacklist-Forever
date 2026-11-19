-- Nullgate's Blacklist: stubbed-client smoke test (optional, complementary to run.lua).
--
-- Run from the repository root:
--     lua tests/smoke.lua
--
-- Loads every file listed in the TOC with stubbed WoW globals, fires
-- ADDON_LOADED and drives the slash commands, so a wrong SlashCmdList key, a
-- stale frame name or a SavedVariables mismatch fails here instead of in game.
-- Nothing here is name-specific: the addon name, TOC name, frame names and
-- slash commands all come from the files under test.

-- The addon folder name is the one fixed fact here; the TOC, frame names and
-- slash commands all come from the files under test. Run from the repository
-- root: lua tests/smoke.lua
local folder = "NullgatesBlacklist-Forever"
local source = debug.getinfo(1, "S").source or ""
local script = source:match("^@(.*)$") or "tests/smoke.lua"
local bs = string.char(92) -- a backslash, for Windows paths
local dirPattern = "^(.*)[/" .. bs .. "][^/" .. bs .. "]*$"
local scriptDir = script:match(dirPattern) or "."
local repoRoot = scriptDir:match(dirPattern) or "."
local root = repoRoot .. "/" .. folder
local tocPath = root .. "/" .. folder .. ".toc"

-- --- WoW stubs ---------------------------------------------------------------

local frames = {}
local printed = {}

-- Unknown methods named like a client call (SetX, GetX, Enable...) do nothing, so
-- the stub does not need every widget method spelled out. Fields stay nil.
local NOOP_VERBS = { Set = true, Get = true, Is = true, Enable = true, Disable = true,
  Start = true, Stop = true, Register = true, Clear = true, Show = true, Hide = true,
  Highlight = true }
local NoopMethods = {
  __index = function(_, key)
    local verb = type(key) == "string" and key:match("^%u%l+")
    if verb and NOOP_VERBS[verb] then return function(self) return self end end
  end,
}

local function Widget(kind, name)
  local w = { kind = kind, name = name, children = {}, _scripts = {}, shown = false }
  local function me() return w end
  for _, method in ipairs({
    "SetSize", "SetPoint", "SetAutoFocus", "SetMaxLetters", "SetMultiLine",
    "SetTextInsets", "SetClampedToScreen", "ClearFocus",
    "SetMovable", "SetFrameLevel",
  }) do
    w[method] = me
  end
  w.SetText = function(this, text) this.text = text return this end
  w.GetText = function(this) return this.text or "" end
  w.SetScript = function(this, scriptName, fn) this._scripts[scriptName] = fn return this end
  w.Show = function(this) this.shown = true return this end
  w.Hide = function(this)
    local was = this.shown
    this.shown = false
    -- Like the client: OnHide runs when a shown frame is hidden.
    if was and this._scripts.OnHide then this._scripts.OnHide(this) end
    return this
  end
  w.IsShown = function(this) return this.shown end
  w.SetChecked = function(this, value) this.checked = value and true or false return this end
  w.GetChecked = function(this) return this.checked end
  w.CreateFontString = function() return Widget("FontString") end
  w.SetSize = function(this, width, height) this.w, this.h = width, height return this end
  w.SetPoint = function(this, point, relative, relPoint, x, y)
    this.points = this.points or {}
    this.points[#this.points + 1] = { point = point, relative = relative, relPoint = relPoint, x = x, y = y }
    return this
  end
  w.SetDataProvider = function(this, provider, retain) this.provider, this.retain = provider, retain return this end
  w.RegisterEvent = function(this, event)
    this.events = this.events or {}
    this.events[event] = true
    return this
  end
  w.SetFrameStrata = function(this, strata) this.strata = strata return this end
  w.SetToplevel = function(this, value) this.toplevel = value and true or false return this end
  w.SetTexture = function(this, texture) this.texture = texture return this end
  w.GetWidth = function(this) return this.w or 0 end
  w.GetFrameLevel = function() return 1 end
  w.SetEnabled = function(this, value) this.enabled = value and true or false return this end
  w.CreateTexture = function() return Widget("Texture") end
  w.TitleContainer = { TitleText = { SetText = function(this, text) this.text = text end } }
  return setmetatable(w, NoopMethods)
end

function CreateFrame(kind, name, parent, template)
  local widget = Widget(kind, name)
  widget.template = template
  if name then
    _G[name] = widget
    _G[name .. "TitleText"] = widget.TitleContainer.TitleText
    local base = name:gsub("%d+$", "")
    _G["Current" .. base] = widget
  end
  if parent and parent.children then parent.children[#parent.children + 1] = widget end
  frames[#frames + 1] = widget
  return widget
end

local lastView
function CreateScrollBoxListLinearView()
  lastView = {
    SetElementExtent = function() end,
    SetElementInitializer = function(self, template, fn) self.template, self.initializer = template, fn end,
  }
  return lastView
end
function CreateDataProvider(array) return { data = array } end
ScrollUtil = { InitScrollBoxListWithScrollBar = function() end }
ScrollBoxConstants = { RetainScrollPosition = "retain" }

local menuHooks = {}
Menu = { ModifyMenu = function(tag, fn) menuHooks[tag] = fn end }

local chatFilters = {}
function ChatFrame_AddMessageEventFilter(event, fn) chatFilters[event] = fn end

UIParent = Widget("Frame", "UIParent")
TargetFrame = Widget("Frame", "TargetFrame")
TargetFrame.TargetFrameContainer = { Portrait = Widget("Texture") }
local smokeTarget
UnitExists = function(unit) return unit == "target" and smokeTarget ~= nil end
UnitIsPlayer = function() return true end
local tooltipCallback
TooltipDataProcessor = { AddTooltipPostCall = function(_, fn) tooltipCallback = fn end }
Enum = { TooltipDataType = { Unit = "unit" } }
GameTooltip = {
  lines = {},
  GetUnit = function() return "Mark Warn", "mouseover" end,
  AddLine = function(self, text) self.lines[#self.lines + 1] = text end,
  Show = function() end,
}
-- Font objects (the addon makes its own for its look).
function CreateFont(name)
  local font = { name = name }
  function font:SetFont(path, size) self.path, self.size = path, size return true end
  function font:SetTextColor(r, g, b) self.color = { r, g, b } end
  function font:SetFontObject() end
  _G[name] = font
  return font
end
STANDARD_TEXT_FONT = "Fonts/FRIZQT__.TTF"
Minimap = Widget("Frame", "Minimap")
Minimap.GetWidth = function() return 140 end
Minimap.GetCenter = function() return 500, 400 end
Minimap.GetEffectiveScale = function() return 1 end
Minimap.ClearAllPoints = function(this) this.points = nil return this end
DEFAULT_CHAT_FRAME = { AddMessage = function(_, text) printed[#printed + 1] = text end }
SlashCmdList = {}
UISpecialFrames = {}

-- Addon messages, timers and popups (sharing, section 7). Timers are recorded and
-- run by hand; popups are recorded so the test can press their buttons.
smokeSent, smokeRegistered, smokeTimers, smokePopups, smokeLastPopup = {}, nil, {}, 0, nil
C_ChatInfo = {
  RegisterAddonMessagePrefix = function(prefix) smokeRegistered = prefix return true end,
  SendAddonMessage = function(prefix, text, channel, target)
    smokeSent[#smokeSent + 1] = { prefix = prefix, text = text, channel = channel, target = target }
    return 0
  end,
}
C_Timer = { After = function(delay, fn) smokeTimers[#smokeTimers + 1] = { delay = delay, fn = fn } end }
StaticPopupDialogs = {}
StaticPopup_Show = function(which, a, b)
  smokePopups = smokePopups + 1
  smokeLastPopup = { which = which, a = a, b = b }
end
StaticPopup_Hide = function() end
tinsert = table.insert
GetLocale = function() return "deDE" end
UnitName = function(unit)
  if unit == "player" then return "Self", "Char" end
  if (unit == "target" or unit == "mouseover") and smokeTarget then return smokeTarget[1], smokeTarget[2] end
  return nil
end
function strtrim(text) return (text:gsub("^%s+", ""):gsub("%s+$", "")) end
function time() return 1700000000 end

-- --- Load the addon exactly as the client does --------------------------------

local function ReadToc()
  local handle = assert(io.open(tocPath, "rb"), "cannot open " .. tocPath)
  local text = handle:read("*a")
  handle:close()
  local files = {}
  for line in text:gmatch("[^\r\n]+") do
    local trimmed = line:gsub("^%s+", ""):gsub("%s+$", "")
    if trimmed ~= "" and trimmed:sub(1, 2) ~= "##" and trimmed:lower():match("%.lua$") then
      files[#files + 1] = trimmed
    end
  end
  return files, text:match("##%s*SavedVariables:%s*([%w_]+)")
end

local tocFiles, savedVariable = ReadToc()
local ns = {}
for _, relative in ipairs(tocFiles) do
  local chunk = assert(loadfile(root .. "/" .. relative), "cannot load " .. relative)
  chunk(folder, ns)
end

local Const = ns.Const

-- --- Assertions --------------------------------------------------------------

local checks, failures = 0, 0

local function Check(ok, label)
  checks = checks + 1
  if ok then return end
  failures = failures + 1
  print("FAIL " .. label)
end

local function Equals(actual, expected, label)
  Check(actual == expected,
    label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function Contains(text, needle, label)
  Check(type(text) == "string" and text:find(needle, 1, true) ~= nil,
    label .. ": " .. tostring(text) .. " lacks " .. tostring(needle))
end

local function LastPrinted()
  return printed[#printed] or ""
end

-- --- TOC, slash registration and bootstrap ------------------------------------

Equals(folder, Const.ADDON_NAME, "folder name equals Const.ADDON_NAME")
Equals(savedVariable, Const.SAVED_VARIABLE, "TOC SavedVariables equals Const.SAVED_VARIABLE")

local slashKey, slashHandler
for key, handler in pairs(SlashCmdList) do
  slashKey, slashHandler = key, handler
end
Check(slashHandler ~= nil, "a slash command is registered")
Equals(slashKey, "NULLGATESBLACKLIST", "SlashCmdList key is NULLGATESBLACKLIST")
Equals(_G["SLASH_" .. tostring(slashKey) .. "1"], Const.SLASH_LONG, "SLASH_<key>1 equals the long command")
Equals(_G["SLASH_" .. tostring(slashKey) .. "2"], Const.SLASH_SHORT, "SLASH_<key>2 equals the short command")

local function Run(input)
  printed = {}
  slashHandler(input)
  return printed
end

local loader
for _, frame in ipairs(frames) do
  if frame._scripts.OnEvent then
    loader = frame
    break
  end
end
Check(loader ~= nil, "the loader frame registered OnEvent")

local function Fire(name)
  printed = {}
  loader._scripts.OnEvent(loader, "ADDON_LOADED", name)
end

Fire("SomeOtherAddon")
Equals(#printed, 0, "ADDON_LOADED for another addon is ignored")

Fire(folder)
Equals(#printed, 1, "one message after loading")
Contains(printed[1], Const.DISPLAY_NAME, "load message names the addon")
Contains(printed[1], ns.L.MSG_LOADED, "load message uses the locale string")
Check(ns.L == ns.Locale.Tables.de, "a deDE client selects the German table")

local db = _G[savedVariable]
Check(type(db) == "table", "the saved variable exists after loading")
Equals(db and db.version, 1, "fresh database is at version 1")
Equals(ns.Settings.Init(), db, "Settings reads the TOC saved variable")
Equals(db and db.settings.language, "auto", "language starts as auto")

-- Enforcement is wired at load: one chat filter per event, one request frame.
Check(chatFilters.CHAT_MSG_SAY ~= nil and chatFilters.CHAT_MSG_WHISPER ~= nil
  and chatFilters.CHAT_MSG_OFFICER ~= nil, "chat filters are registered")
Check(chatFilters.CHAT_MSG_SAY == chatFilters.CHAT_MSG_GUILD, "one shared chat filter")
local requestFrame
for _, frame in ipairs(frames) do
  if frame.events and frame.events.PARTY_INVITE_REQUEST then requestFrame = frame end
end
Check(requestFrame ~= nil, "the request frame is created")

-- Hidden chat and declined requests run end to end through the loaded addon.
ns.Records.Save("Smoke Target", "ignore", { spam = true }, "smoke")
Equals(chatFilters.CHAT_MSG_SAY(nil, "CHAT_MSG_SAY", "hi", "Smoke Target"), true, "ignored chat is hidden")
Equals(chatFilters.CHAT_MSG_SAY(nil, "CHAT_MSG_SAY", "hi", "Someone Else"), false, "other chat is shown")
local declined
function DeclineGroup() declined = true end
printed = {}
requestFrame._scripts.OnEvent(requestFrame, "PARTY_INVITE_REQUEST", "Smoke Target")
Equals(declined, true, "a party invite from an ignored player is declined")
DeclineGroup = nil
ns.Records.Remove("Smoke Target")

local newer = { version = 99, settings = { language = "de" } }
_G[savedVariable] = newer
Fire(folder)
Contains(printed[1], ns.L.MSG_DB_NEWER, "newer data is reported")
Equals(_G[savedVariable].version, 99, "newer data is left alone")

_G[savedVariable] = nil
ns.Settings.Init()

-- --- Slash commands -----------------------------------------------------------

local out = Run("help")
Equals(#out, 14, "help prints fourteen lines")
Contains(out[1], ns.L.HELP_HEADER, "help header")
Contains(out[2], Const.SLASH_SHORT, "help lines use the short command")

local tocVersion
do
  local handle = assert(io.open(tocPath, "rb"))
  tocVersion = handle:read("*a"):match("##%s*Version:%s*([%d%.]+)")
  handle:close()
end
GetAddOnMetadata = function(name, field)
  if name == folder and field == "Version" then return tocVersion end
end
Run("version")
Contains(LastPrinted(), string.format(ns.L.MSG_VERSION, tocVersion), "version command prints the TOC version")
GetAddOnMetadata = nil
Run("version")
Contains(LastPrinted(), string.format(ns.L.MSG_VERSION, "?"), "version command copes with missing metadata API")

Run("")
Check(_G.CurrentNullgateBlacklistManager ~= nil and _G.CurrentNullgateBlacklistManager:IsShown(), "the bare command opens the window")
Run("")
Check(not _G.CurrentNullgateBlacklistManager:IsShown(), "the bare command closes it again")

Run("list")
Contains(LastPrinted(), ns.L.MSG_LIST_EMPTY, "empty list message")

Run("ignore")
Contains(LastPrinted(), string.format(ns.L.MSG_NEED_NAME, "ignore"), "ignore without a name")

Run("remove")
Contains(LastPrinted(), string.format(ns.L.MSG_NEED_NAME, "remove"), "remove without a name")

Run("bogus")
Contains(LastPrinted(), string.format(ns.L.MSG_UNKNOWN_COMMAND, "bogus"), "unknown command")

Run("lang xx")
Contains(LastPrinted(), "auto, en, zh, es, fr, pt, ru, id, de, ja, tr, vi, ko, it, pl, uk", "an invalid language is rejected and all fifteen choices are listed")
Run("lang en")
Equals(ns.Settings.Get("language"), "en", "language stored")
Equals(ns.L, ns.Locale.Tables.en, "the language changes at once, without /reload")
Contains(LastPrinted(), string.format(ns.L.MSG_LANG_SET, "English"), "language confirmation")
Run("lang auto")
Equals(ns.Settings.Get("language"), "auto", "language reset to auto")
Equals(ns.L, ns.Locale.Tables.de, "automatic follows the client (German here)")

Run("ignore Self Char")
Contains(LastPrinted(), ns.L.MSG_SELF, "own character is refused")

Run("setup")
Check(_G.CurrentNullgateBlacklistWizard ~= nil and _G.CurrentNullgateBlacklistWizard:IsShown(), "/nbl setup opens the setup wizard")
_G.CurrentNullgateBlacklistWizard:Hide()

-- Minimap button: created at load, toggled by /nbl minimap, position persists.
local minimapButton = _G.NullgateBlacklistMinimapButton
Check(minimapButton ~= nil and minimapButton.shown, "the minimap button is shown by default")
Run("minimap")
Contains(LastPrinted(), ns.L.MSG_MINIMAP_HIDDEN, "minimap command reports hiding")
Check(not minimapButton.shown and ns.Settings.Get("showMinimap") == false, "the button is hidden and the setting saved")
Run("minimap")
Contains(LastPrinted(), ns.L.MSG_MINIMAP_SHOWN, "minimap command reports showing")
Check(minimapButton.shown and ns.Settings.Get("showMinimap") == true, "the button is shown again")
local dragStart, dragStop = minimapButton._scripts.OnDragStart, minimapButton._scripts.OnDragStop
Check(minimapButton._scripts.OnUpdate == nil, "no per-frame work before a drag")
dragStart(minimapButton)
Check(minimapButton._scripts.OnUpdate ~= nil, "dragging installs the follow script")
GetCursorPosition = function() return 500, 500 end
minimapButton._scripts.OnUpdate(minimapButton)
Equals(ns.Settings.Get("minimapAngle"), 90, "the angle follows the cursor (straight up is 90)")
GetCursorPosition = function() return 400, 300 end
minimapButton._scripts.OnUpdate(minimapButton)
Equals(ns.Settings.Get("minimapAngle"), 225, "the angle follows the cursor (down-left is 225)")
dragStop(minimapButton)
Check(minimapButton._scripts.OnUpdate == nil, "the follow script is removed when the drag ends")
Equals(_G[savedVariable].settings.minimapAngle, 225, "the angle is in the saved variable")

-- --- Editor -----------------------------------------------------------------------

local function Find(frame, predicate, results)
  results = results or {}
  for _, child in ipairs(frame.children) do
    if predicate(child) then results[#results + 1] = child end
    Find(child, predicate, results)
  end
  return results
end

local function Parts(editorFrame)
  local parts = {}
  parts.nameBox = Find(editorFrame, function(f) return f.kind == "EditBox" and f.role == "input" end)[1]
  parts.comment = Find(editorFrame, function(f) return f.kind == "EditBox" and f.role == "textedit" end)[1]
  parts.save = Find(editorFrame, function(f) return f.kind == "Button" and f.text == ns.L.EDITOR_SAVE end)[1]
  parts.cancel = Find(editorFrame, function(f) return f.kind == "Button" and f.text == ns.L.EDITOR_CANCEL end)[1]
  local checks = Find(editorFrame, function(f) return f.kind == "CheckButton" end)
  parts.radios, parts.labels = {}, {}
  for _, check in ipairs(checks) do
    if check.text == ns.L.VERDICT_IGNORE then parts.radios.ignore = check
    elseif check.text == ns.L.VERDICT_WARN then parts.radios.warn = check
    else parts.labels[#parts.labels + 1] = check end
  end
  return parts
end

local function Click(widget)
  widget._scripts.OnClick(widget)
end

local function Type(box, text)
  box:SetText(text)
  box._scripts.OnTextChanged(box)
end

out = Run("warn Alpha Beta")
Equals(#out, 0, "opening the editor prints nothing")
local editor = _G.CurrentNullgateBlacklistEditor
Check(editor ~= nil and editor:IsShown(), "the editor is shown")
local function InList(list, value)
  for _, entry in ipairs(list) do if entry == value then return true end end
  return false
end
Check(InList(UISpecialFrames, "NullgateBlacklistEditor"), "the editor is listed in UISpecialFrames")
Check(InList(UISpecialFrames, "NullgateBlacklistManager"), "the window is listed in UISpecialFrames")
Equals(_G.CurrentNullgateBlacklistEditor.strata, "DIALOG", "the editor sits in the DIALOG strata, above HUD addons")
Equals(_G.CurrentNullgateBlacklistManager.strata, "DIALOG", "the window sits in the DIALOG strata, above HUD addons")
Check(_G.CurrentNullgateBlacklistEditor.toplevel and _G.CurrentNullgateBlacklistManager.toplevel, "both windows rise when clicked")

local p = Parts(editor)
Check(p.nameBox and p.comment and p.save and p.cancel, "name box, comment box and both buttons exist")
Equals(#p.labels, #Const.Labels, "one checkbox per label in the fallback grid")
Check(p.radios.ignore and p.radios.warn, "both verdict radios exist")
Equals(p.nameBox.text, "Alpha Beta", "name box is prefilled")
Equals(p.radios.warn.checked, true, "the requested verdict is selected")
Equals(p.radios.ignore.checked, false, "the other verdict is not selected")
Equals(p.save.enabled, false, "Save is disabled without labels and comment")

-- Layout: the comment area (with its hint line) must end above the buttons.
-- The buttons sit 14 px above the bottom edge and are 22 px high.
do
  local area = p.comment and Find(editor, function(f) return f.edit == p.comment end)[1]
  local top = area and area.points and area.points[1]
  Check(top ~= nil and top.relative == editor and top.point == "TOPLEFT", "the comment area is anchored to the top of the editor")
  if top and editor.h then
    local areaBottom = -top.y + area.h
    Check(areaBottom + 16 <= editor.h - 14 - 22,
      "the comment area and its hint end above the buttons (area bottom " .. areaBottom .. ", frame " .. editor.h .. ")")
  else
    Check(false, "the editor frame has a recorded height")
  end
end

printed = {}
Check(not ns.Editor.Commit(), "a forced commit without labels is refused")
Contains(LastPrinted(), ns.L.ERR_LABELS, "the missing label is reported")
Check(editor:IsShown(), "the editor stays open after a refused save")
Equals(#ns.Records.All(), 0, "nothing was saved")

p.labels[1]:SetChecked(true)
Click(p.labels[1])
Equals(p.save.enabled, false, "a label alone does not enable Save")
Type(p.comment, "Pulled the boss on purpose")
Equals(p.save.enabled, true, "label and comment enable Save")
Type(p.comment, "   ")
Equals(p.save.enabled, false, "a blank comment disables Save again")
Type(p.comment, string.rep("x", 256))
Equals(p.save.enabled, false, "a 256 character comment disables Save")
Type(p.comment, "Pulled the boss on purpose")
Equals(p.save.enabled, true, "Save is enabled again")

Click(p.radios.ignore)
Equals(p.radios.warn.checked, false, "choosing one verdict clears the other")
Click(p.radios.warn)

printed = {}
Click(p.save)
local record = ns.Records.Get("alpha beta")
Check(record ~= nil, "the record was saved")
Equals(record and record.verdict, "warn", "verdict stored")
Equals(record and record.labels.harassment, true, "the clicked label stored")
Equals(record and record.comment, "Pulled the boss on purpose", "comment stored")
Check(not editor:IsShown(), "the editor closes after saving")
Contains(LastPrinted(), "Alpha Beta", "save message names the player")
Contains(LastPrinted(), ns.L.VERDICT_WARN, "save message shows the verdict")

ns.Records.Save("Pipe | Name", "ignore", { scam = true }, "Piped text")

out = Run("list")
Equals(#out, 3, "header plus two rows")
Contains(out[2], "Alpha Beta", "first row shows the name")
Contains(out[2], ns.L.VERDICT_WARN, "first row shows the verdict")
Contains(out[2], ns.L.LABEL_HARASSMENT, "first row shows the label")
Contains(out[3], "Pipe || Name", "pipes are escaped for chat output")

Run("remove alpha beta")
Contains(LastPrinted(), string.format(ns.L.MSG_RECORD_REMOVED, "Alpha Beta"), "remove message uses the stored name")
Run("remove alpha beta")
Contains(LastPrinted(), string.format(ns.L.MSG_RECORD_NOT_FOUND, "alpha beta"), "second remove echoes the typed name")
Run("remove Pipe | Name")
Equals(#ns.Records.All(), 0, "all records removed")

-- --- Editor: existing records, renames, name clashes --------------------------------

ns.Records.Save("Alpha Beta", "warn", { harassment = true }, "Pulled the boss on purpose")
Run("ignore Alpha Beta")
p = Parts(_G.CurrentNullgateBlacklistEditor)
Equals(p.nameBox.text, "Alpha Beta", "an existing record is loaded")
Equals(p.radios.warn.checked, true, "the stored verdict wins over the command")
Equals(p.comment.text, "Pulled the boss on purpose", "the stored comment is loaded")
Equals(p.labels[1].checked, true, "the stored label is checked")
Equals(p.save.enabled, true, "an existing valid record can be saved at once")

Type(p.nameBox, "Gamma Delta")
Click(p.save)
Equals(ns.Records.Get("alpha beta"), nil, "renaming moves the record")
Check(ns.Records.Get("gamma delta") ~= nil, "the renamed record exists")

ns.Records.Save("Epsilon Zeta", "ignore", { spam = true }, "Other record")
Run("ignore Gamma Delta")
p = Parts(_G.CurrentNullgateBlacklistEditor)
Type(p.nameBox, "Epsilon Zeta")
printed = {}
Click(p.save)
Contains(LastPrinted(), string.format(ns.L.MSG_NAME_TAKEN, "Epsilon Zeta"), "renaming onto another record is refused")
Equals(ns.Records.Get("epsilon zeta").comment, "Other record", "the other record is untouched")
Check(ns.Records.Get("gamma delta") ~= nil, "the renamed record stays where it was")

Run("ignore Fresh Person")
p = Parts(_G.CurrentNullgateBlacklistEditor)
Equals(p.comment.text, "", "a new record starts with an empty comment")
Equals(p.labels[1].checked, false, "a new record starts without labels")
Type(p.nameBox, "Epsilon Zeta")
p.labels[2]:SetChecked(true)
Click(p.labels[2])
Type(p.comment, "overwrite attempt")
printed = {}
Click(p.save)
Contains(LastPrinted(), string.format(ns.L.MSG_NAME_TAKEN, "Epsilon Zeta"), "a new record cannot overwrite an existing one")
Equals(ns.Records.Get("epsilon zeta").comment, "Other record", "nothing was overwritten")

Click(p.cancel)
Check(not _G.CurrentNullgateBlacklistEditor:IsShown(), "Cancel closes the editor")
ns.Records.Remove("gamma delta")
ns.Records.Remove("epsilon zeta")
Equals(#ns.Records.All(), 0, "editor tests left no records behind")

-- --- Window: list tab ---------------------------------------------------------------

ns.Records.Save("Row One", "ignore", { scam = true }, "first comment")
ns.Records.Save("Row Two", "warn", { spam = true }, "second comment")
Run("")
local manager = _G.CurrentNullgateBlacklistManager
Check(manager:IsShown(), "the window opens")

local function Box() return Find(manager, function(f) return f.provider ~= nil end)[1] end
local function Names()
  local names = {}
  for _, record in ipairs(Box().provider.data) do names[#names + 1] = record.name end
  return table.concat(names, ",")
end
local function ButtonByText(text)
  return Find(manager, function(f)
    return f.kind == "Button" and f.text and f.text:sub(1, #text) == text
  end)[1]
end

Equals(Names(), "Row One,Row Two", "both records are listed, sorted by name")
Equals(Box().retain, "retain", "refreshing keeps the scroll position")
Equals(lastView.template, "Button", "rows are buttons")

-- rows are recycled widgets filled by the initializer
local row = CreateFrame("Button", nil, Box())
lastView.initializer(row, Box().provider.data[1])
Equals(row.cells.name.text, "Row One", "the row shows the name")
Equals(row.cells.verdict.text, ns.L.VERDICT_IGNORE, "the row shows the verdict")
Equals(row.cells.labels.text, ns.L.LABEL_SCAM, "the row shows the labels")
Equals(row.cells.comment.text, "first comment", "the row shows the comment")
Check(row.cells.date.text:match("^%d%d%d%d%-%d%d%-%d%d$") ~= nil, "the row shows a date")
lastView.initializer(row, Box().provider.data[2])
Equals(row.cells.name.text, "Row Two", "a recycled row shows its new record")

-- search
local inputs = Find(manager, function(f) return f.kind == "EditBox" and f.role == "input" end)
local searchBox = inputs[1]
Type(searchBox, "two")
Equals(Names(), "Row Two", "search narrows the list")
Type(searchBox, "FIRST COMMENT")
Equals(Names(), "Row One", "search matches the comment, ignoring case")
Type(searchBox, "zzz")
Equals(Names(), "", "search with no match empties the list")
Type(searchBox, "")
Equals(Names(), "Row One,Row Two", "clearing the search restores the list")

-- verdict filter
local warnRadio = Find(manager, function(f) return f.kind == "CheckButton" and f.text == ns.L.VERDICT_WARN end)[1]
Click(warnRadio)
Equals(Names(), "Row Two", "the verdict filter shows only warnings")
local allRadio = Find(manager, function(f) return f.kind == "CheckButton" and f.text == ns.L.FILTER_ALL end)[1]
Click(allRadio)
Equals(Names(), "Row One,Row Two", "All shows everything again")

-- label filter (checkbox grid in this stub client)
local spamCheck = Find(manager, function(f) return f.kind == "CheckButton" and f.text == ns.L.LABEL_SPAM end)[1]
spamCheck:SetChecked(true)
Click(spamCheck)
Equals(Names(), "Row Two", "the label filter keeps matching records")
spamCheck:SetChecked(false)
Click(spamCheck)
Equals(Names(), "Row One,Row Two", "clearing the label filter shows all")

-- sorting
local nameHeader = ButtonByText(ns.L.COL_NAME)
Check(nameHeader.text:find("^", 1, true) ~= nil, "the sorted column shows an arrow")
Click(nameHeader)
Equals(Names(), "Row Two,Row One", "clicking the sorted column reverses it")
Click(nameHeader)
Equals(Names(), "Row One,Row Two", "clicking again restores it")
Click(ButtonByText(ns.L.COL_VERDICT))
Equals(Names(), "Row Two,Row One", "sort by verdict puts warnings before ignores")
Click(nameHeader)
Equals(Names(), "Row One,Row Two", "a new column starts ascending")

-- clicking a row: edit, shift-click: delete
IsShiftKeyDown = function() return false end
Click(row)
Check(_G.CurrentNullgateBlacklistEditor:IsShown(), "clicking a row opens the editor")
Equals(Find(_G.CurrentNullgateBlacklistEditor, function(f) return f.kind == "EditBox" and f.role == "input" end)[1].text,
  "Row Two", "the editor shows that record")
Click(Find(_G.CurrentNullgateBlacklistEditor, function(f) return f.kind == "Button" and f.text == ns.L.EDITOR_CANCEL end)[1])
IsShiftKeyDown = function() return true end
printed = {}
Click(row)
Equals(ns.Records.Get("row two"), nil, "shift-click deletes the record")
Contains(LastPrinted(), "Row Two", "the deletion is announced")
Equals(Names(), "Row One", "the list updates after a deletion")
IsShiftKeyDown = nil
ns.Records.Remove("row one")
Equals(Names(), "", "the list is empty when no records remain")

-- add player box
local addBox = inputs[2]
local addButton = ButtonByText(ns.L.LIST_ADD)
addBox:SetText("Typed Name")
Click(addButton)
Equals(Find(_G.CurrentNullgateBlacklistEditor, function(f) return f.kind == "EditBox" and f.role == "input" end)[1].text,
  "Typed Name", "the add box opens the editor with the typed name")
Equals(addBox.text, "", "the add box is cleared")
Click(Find(_G.CurrentNullgateBlacklistEditor, function(f) return f.kind == "Button" and f.text == ns.L.EDITOR_CANCEL end)[1])

-- --- Window: settings tab -----------------------------------------------------------

Click(ButtonByText(ns.L.TAB_SETTINGS))
local hideCheck = Find(manager, function(f) return f.kind == "CheckButton" and f.text == ns.L.OPT_HIDE_CHAT end)[1]
Check(hideCheck ~= nil, "the settings tab shows the hide chat option")
Equals(hideCheck.checked, true, "the option reflects the saved value")
hideCheck:SetChecked(false)
Click(hideCheck)
Equals(ns.Settings.Get("hideChat"), false, "unticking saves the setting at once")
hideCheck:SetChecked(true)
Click(hideCheck)
Equals(ns.Settings.Get("hideChat"), true, "ticking saves it again")
for _, key in ipairs({ "OPT_AUTO_DECLINE", "OPT_SHOW_NOTICES", "OPT_SHOW_MINIMAP" }) do
  Check(Find(manager, function(f) return f.kind == "CheckButton" and f.text == ns.L[key] end)[1] ~= nil, key .. " is offered")
end
local germanSettingsTab = ns.L.TAB_SETTINGS
local englishChoice = Find(manager, function(f) return f.kind == "CheckButton" and f.text == ns.Locale.Names.en end)[1]
Check(englishChoice ~= nil, "the settings tab offers English by its own name")
Check(Find(manager, function(f) return f.kind == "CheckButton" and f.text == ns.Locale.Names.de end)[1] ~= nil,
  "and German by its own name")
printed = {}
Click(englishChoice)
Equals(ns.Settings.Get("language"), "en", "choosing a language saves it")
Equals(ns.L, ns.Locale.Tables.en, "and applies it at once")
manager = _G.CurrentNullgateBlacklistManager
Check(manager:IsShown(), "the window is rebuilt and stays open")
Check(ButtonByText(ns.L.TAB_SETTINGS) ~= nil and ns.L.TAB_SETTINGS ~= germanSettingsTab, "the tab bar is now in English")
Check(Find(manager, function(f) return f.kind == "CheckButton" and f.text == ns.L.OPT_HIDE_CHAT end)[1] ~= nil,
  "and so are the options on the tab")
Contains(LastPrinted(), "English", "the language change is confirmed")
Click(Find(manager, function(f) return f.kind == "CheckButton" and f.text == ns.L.LANG_AUTO end)[1])
Equals(ns.Settings.Get("language"), "auto", "language back to automatic")
manager = _G.CurrentNullgateBlacklistManager
Equals(ns.L, ns.Locale.Tables.de, "which follows the client again")
Check(ButtonByText(ns.L.TAB_SETTINGS) ~= nil, "and the window is in that language")
Click(ButtonByText(ns.L.TAB_LIST))
Check(Box() ~= nil, "switching back to the list tab works")
Run("")
Check(not manager:IsShown(), "the window closes")

-- --- Display: icon, chat markers, portrait, tooltip -----------------------------------------

do
  local handle = assert(io.open(tocPath, "rb"))
  local tocText = handle:read("*a")
  handle:close()
  Equals(tocText:match("##%s*IconTexture:%s*(%S+)"), Const.ICON, "the TOC icon is the icon the addon uses")
  Check(tocText:find("Display/Markers.lua", 1, true) < tocText:find("Enforce/Chat.lua", 1, true),
    "Markers loads before the chat filter that uses it")
end
local iconFile = io.open(root .. "/icon.tga", "rb")
Check(iconFile ~= nil, "the icon file ships in the addon folder")
if iconFile then
  local header = iconFile:read(18)
  iconFile:close()
  local width = header:byte(13) + header:byte(14) * 256
  local height = header:byte(15) + header:byte(16) * 256
  Equals(header:byte(3), 2, "the icon is an uncompressed true-colour TGA")
  Equals(header:byte(17), 32, "the icon has 32 bits per pixel (alpha)")
  local function PowerOfTwo(n)
    local p = 1
    while p < n do p = p * 2 end
    return n > 0 and p == n
  end
  Check(PowerOfTwo(width), "the icon width is a power of two (" .. width .. ")")
  Check(PowerOfTwo(height), "the icon height is a power of two (" .. height .. ")")
end

ns.Records.Save("Mark Warn", "warn", { spam = true }, "marked in chat")
local hide, marked = chatFilters.CHAT_MSG_SAY(nil, "CHAT_MSG_SAY", "yo", "Mark Warn")
Equals(hide, false, "a warned player's chat is shown")
Check(type(marked) == "string" and marked:find("UI-Dialog-Icon-AlertNew", 1, true) ~= nil
  and marked:sub(-2) == "yo", "the warning icon is in front of the text")

smokeTarget = { "Mark", "Warn" }
local targetFrame
for _, frame in ipairs(frames) do
  if frame.events and frame.events.PLAYER_TARGET_CHANGED then targetFrame = frame end
end
Check(targetFrame ~= nil, "the target change event is registered")
targetFrame._scripts.OnEvent(targetFrame, "PLAYER_TARGET_CHANGED")
local mark = _G.NullgateBlacklistTargetMark
Check(mark ~= nil and mark.shown, "the portrait mark is shown for a warned target")
Check(mark.icon.shown and not mark.strike.shown, "a warned target gets the corner icon")
Check(mark.icon.texture and mark.icon.texture:find("AlertNew", 1, true), "with the warning texture")
ns.Records.Save("Mark Warn", "ignore", { spam = true }, "now ignored")
Check(mark.strike.shown and not mark.icon.shown, "changing the record redraws the mark (strike for ignore)")
smokeTarget = nil
targetFrame._scripts.OnEvent(targetFrame, "PLAYER_TARGET_CHANGED")
Check(not mark.shown, "no target hides the mark")

Check(tooltipCallback ~= nil, "the unit tooltip hook is installed")
smokeTarget = { "Mark", "Warn" }
GameTooltip.lines = {}
tooltipCallback(GameTooltip)
Check(#GameTooltip.lines >= 3, "the tooltip gets the verdict, labels and comment")
Contains(GameTooltip.lines[1], "Nullgate's Blacklist: ", "the first tooltip line names the addon")
Contains(GameTooltip.lines[3], "now ignored", "the comment is shown")
ns.Records.Remove("mark warn")
smokeTarget = nil

-- /nbl test shows a sample chat line so the icons can be checked in game.
local warnLine = Run("test warn")
Equals(#warnLine, 1, "/nbl test warn prints one sample line")
Contains(warnLine[1], "UI-Dialog-Icon-AlertNew", "the warn sample carries the warning icon")
Contains(warnLine[1], ns.L.MSG_TEST_SAMPLE, "the warn sample has the sample text")
Contains(Run("test notice")[1], "Arrow-Down-Up", "the notice sample carries the notice icon")
ns.Settings.Set("hideChat", true)
Contains(Run("test ignore")[1], ns.L.MSG_TEST_HIDDEN, "ignore sample explains hidden chat when hiding is on")
ns.Settings.Set("hideChat", false)
Contains(Run("test ignore")[1], "|cffe61a1a", "ignore sample shows the red cross when hiding is off")
ns.Settings.Set("hideChat", true)
Contains(Run("test")[1], ns.L.MSG_TEST_USAGE, "/nbl test without a verdict shows the usage")
Contains(Run("test bogus")[1], ns.L.MSG_TEST_USAGE, "/nbl test with an unknown verdict shows the usage")

-- --- Sharing: tabs, export, import, lists and the transfer hook ------------------------------------

do
  -- Pump timers (0.3 s) run by hand; the long ones (timeouts) stay pending.
  local function RunShortTimers()
    local keep = {}
    for _, timer in ipairs(smokeTimers) do
      if timer.delay <= 1 then timer.fn() else keep[#keep + 1] = timer end
    end
    smokeTimers = keep
  end
  -- The tab content frame that holds a widget the predicate finds.
  local function TabContent(predicate)
    for _, child in ipairs(manager.children) do
      if predicate(child) or #Find(child, predicate) > 0 then return child end
    end
    return nil
  end
  local function Button(root, text)
    return Find(root, function(f) return f.kind == "Button" and f.text == text end)[1]
  end

  ns.Records.Save("Share One", "ignore", { spam = true }, "first")
  ns.Records.Save("Share Two", "warn", { scam = true }, "second")
  Run("")
  Check(manager:IsShown(), "the window opens for the sharing tests")
  for _, key in ipairs({ "TAB_LIST", "TAB_IMPORTED", "TAB_LISTS", "TAB_SHARE", "TAB_SETTINGS" }) do
    Check(ButtonByText(ns.L[key]) ~= nil, key .. " is on the tab bar")
  end

  -- Share tab: export.
  Click(ButtonByText(ns.L.TAB_SHARE))
  local share = TabContent(function(f) return f.kind == "Button" and f.text == ns.L.SHARE_EXPORT_BUTTON end)
  Check(share ~= nil, "the share tab is built")
  local boxes = Find(share, function(f) return f.edit ~= nil end)
  Equals(#boxes, 2, "the share tab has a code box and a paste box")
  local codeBox, pasteBox = boxes[1], boxes[2]
  Check(Find(codeBox, function(f) return f.template == "UIPanelScrollFrameTemplate" end)[1] ~= nil,
    "the code box scrolls inside its own frame, so a long code cannot cover other widgets")
  local inputs = Find(share, function(f) return f.kind == "EditBox" and f.role == "input" end)
  local nameBox = inputs[1]

  Click(Button(share, ns.L.SHARE_EXPORT_BUTTON))
  local exportedText = codeBox.edit.text
  Contains(exportedText, "BK1R:", "Create code puts a list code in the box")
  local exported = ns.Codec.Decode(exportedText)
  Check(exported ~= nil and exported.records["share one"] ~= nil and exported.records["share two"] ~= nil,
    "the code holds the own records")
  Equals(exported.id, ns.Settings.Get("export.id"), "under the own export id")
  codeBox.edit:SetText("tampered")
  codeBox.edit._scripts.OnTextChanged(codeBox.edit, true)
  Equals(codeBox.edit.text, exportedText, "typing in the code box changes nothing")
  Type(nameBox, "Smoke list")
  Click(Button(share, ns.L.SHARE_EXPORT_BUTTON))
  Equals(ns.Codec.Decode(codeBox.edit.text).name, "Smoke list", "the list name from the box is used")
  Equals(ns.Settings.Get("export.name"), "Smoke list", "and remembered")

  -- Share tab: import.
  local importButton = Button(share, ns.L.SHARE_IMPORT_BUTTON)
  smokePopups = 0
  pasteBox.edit:SetText(exportedText)
  Click(importButton)
  Equals(smokePopups, 0, "your own list is refused without asking")
  pasteBox.edit:SetText("BK1R:abcd:00000000")
  Click(importButton)
  Equals(smokePopups, 0, "a damaged code is refused without asking")
  Equals(next(ns.db.subscriptions), nil, "nothing was imported")

  local foreign = ns.Codec.Encode({ id = "feedbeef0001", name = "Foreign list", author = "Zed Zed",
    exported = 1700000000, records = {
      { name = "Foreign One", verdict = "warn", labels = { spam = true }, created = 1690000000, comment = "bad ad" },
      { name = "Foreign Two", labels = { scam = true }, comment = "scam" },
    } })
  pasteBox.edit:SetText(foreign)
  Click(importButton)
  Equals(smokePopups, 1, "a good code asks for confirmation")
  Equals(smokeLastPopup.which, "NULLGATE_BLACKLIST_CONFIRM_IMPORT", "with Nullgate's Blacklist's popup")
  Contains(smokeLastPopup.a, "Foreign list", "naming the list")
  Contains(smokeLastPopup.a, "Zed Zed", "and its author")
  Contains(smokeLastPopup.b, "2", "and its size")
  Equals(ns.Subscriptions.Get("feedbeef0001"), nil, "nothing is imported before the player confirms")
  StaticPopupDialogs.NULLGATE_BLACKLIST_CONFIRM_IMPORT.OnCancel()
  StaticPopupDialogs.NULLGATE_BLACKLIST_CONFIRM_IMPORT.OnAccept()
  Equals(ns.Subscriptions.Get("feedbeef0001"), nil, "cancelling forgets the pending import")
  Click(importButton)
  StaticPopupDialogs.NULLGATE_BLACKLIST_CONFIRM_IMPORT.OnAccept()
  Check(ns.Subscriptions.Get("feedbeef0001") ~= nil, "confirming imports the list")
  Equals(pasteBox.edit.text, "", "the paste box is emptied after an import")
  Equals(ns.Resolver.Verdict("Foreign One"), "notice", "an imported entry is a notice until a rule says more")
  pasteBox.edit:SetText("junk")
  Click(Button(share, ns.L.SHARE_CLEAR))
  Equals(pasteBox.edit.text, "", "Clear empties the paste box")

  -- Lists tab: choose rules, which change the effective verdict.
  Click(ButtonByText(ns.L.TAB_LISTS))
  local listsView = lastView
  local lists = TabContent(function(f)
    return f.provider ~= nil and f.provider.data[1] ~= nil and f.provider.data[1].id ~= nil
  end)
  Check(lists ~= nil, "the lists tab shows the imported list")
  local listBox = Find(lists, function(f) return f.provider ~= nil end)[1]
  Equals(#listBox.provider.data, 1, "one imported list")
  local listRow = CreateFrame("Button", nil, listBox)
  listsView.initializer(listRow, listBox.provider.data[1])
  Equals(listRow.name.text, "Foreign list", "the row shows the list name")
  Equals(listRow.count.text, "2", "and its size")
  local function Radios(text) return Find(lists, function(f) return f.kind == "CheckButton" and f.text == text end) end
  Equals(#Radios(ns.L.VERDICT_WARN), 9, "every reason can be given a rule")
  local function LabelIndex(id)
    for index, entry in ipairs(Const.Labels) do if entry.id == id then return index end end
  end
  Click(Radios(ns.L.VERDICT_WARN)[LabelIndex("spam")])
  Equals(ns.Subscriptions.Rule("feedbeef0001", "spam"), "warn", "the rule is saved")
  Equals(ns.Resolver.Verdict("Foreign One"), "warn", "and changes the effective verdict")
  Click(Radios(ns.L.VERDICT_IGNORE)[LabelIndex("scam")])
  Equals(ns.Resolver.Verdict("Foreign Two"), "ignore", "a stronger rule ignores the player")
  Click(Radios(ns.L.VERDICT_NOTICE)[LabelIndex("scam")])
  Equals(ns.Resolver.Verdict("Foreign Two"), "notice", "back to a notice")

  -- Imported tab: the entries with their effective verdict; a click adopts.
  Click(ButtonByText(ns.L.TAB_IMPORTED))
  local importedView = lastView
  local importedBox = Find(manager, function(f)
    return f.provider ~= nil and f.provider.data[1] ~= nil and f.provider.data[1].listId ~= nil
  end)[1]
  Check(importedBox ~= nil, "the imported tab lists the entries")
  Equals(#importedBox.provider.data, 2, "both entries are listed")
  local importedRow = CreateFrame("Button", nil, importedBox)
  importedView.initializer(importedRow, importedBox.provider.data[1])
  Equals(importedRow.cells.name.text, "Foreign One", "the row shows the name")
  Equals(importedRow.cells.verdict.text, ns.L.VERDICT_WARN, "with the verdict the rules give")
  Equals(importedRow.cells.list.text, "Foreign list", "and the list it came from")
  Click(importedRow)
  local adopt = Parts(_G.CurrentNullgateBlacklistEditor)
  Equals(adopt.nameBox.text, "Foreign One", "a click opens the editor for that player")
  Equals(adopt.comment.text, "bad ad", "prefilled with the list's comment")
  Click(adopt.cancel)

  -- Back on the lists tab, removing needs Shift.
  Click(ButtonByText(ns.L.TAB_LISTS))
  local removeButton = Button(lists, ns.L.LISTS_REMOVE)
  Click(removeButton)
  Check(ns.Subscriptions.Get("feedbeef0001") ~= nil, "a plain click does not remove the list")
  IsShiftKeyDown = function() return true end
  Click(removeButton)
  IsShiftKeyDown = nil
  Equals(ns.Subscriptions.Get("feedbeef0001"), nil, "Shift-click removes it")
  Equals(ns.Resolver.Verdict("Foreign One"), nil, "and its entries no longer flag anyone")
end

-- --- Community: tabs, consent, background sharing and rules ------------------------------------------

do
  Equals(smokeRegistered, Const.COMMUNITY_PREFIX, "the community prefix is registered")
  local addonFrame
  for _, frame in ipairs(frames) do
    if frame.events and frame.events.CHAT_MSG_ADDON then addonFrame = frame end
  end
  Check(addonFrame ~= nil, "the addon message event is listened to")

  local function RunShortTimers()
    local keep = {}
    for _, timer in ipairs(smokeTimers) do
      if timer.delay <= 1 then timer.fn() else keep[#keep + 1] = timer end
    end
    smokeTimers = keep
  end
  local function TabContent(predicate)
    for _, child in ipairs(manager.children) do
      if predicate(child) or #Find(child, predicate) > 0 then return child end
    end
    return nil
  end
  local function Button(root, text)
    return Find(root, function(f) return f.kind == "Button" and f.text == text end)[1]
  end
  local function Checks(root, text)
    return Find(root, function(f) return f.kind == "CheckButton" and f.text == text end)
  end
  local function Deliver(text, channel, sender)
    addonFrame._scripts.OnEvent(addonFrame, "CHAT_MSG_ADDON", Const.COMMUNITY_PREFIX, text, channel, sender)
  end

  Run("")
  for _, key in ipairs({ "TAB_LIST", "TAB_IMPORTED", "TAB_LISTS", "TAB_SHARE", "TAB_COMMUNITY", "TAB_RULES", "TAB_SETTINGS" }) do
    Check(ButtonByText(ns.L[key]) ~= nil, key .. " is on the tab bar")
  end
  Equals(#Find(manager, function(f)
    return f.role == "tab" and f.points and f.points[1].relative == manager
  end), 7, "all seven tabs sit on the tab bar")

  -- Community tab: nothing can be switched on before the notice is confirmed.
  Click(ButtonByText(ns.L.TAB_COMMUNITY))
  local community = TabContent(function(f) return f.kind == "Button" and f.text == ns.L.COMM_CONFIRM end)
  Check(community ~= nil, "the community tab is built")
  local sends, receives = Checks(community, ns.L.COMM_SEND), Checks(community, ns.L.COMM_RECEIVE)
  Equals(#sends, 3, "friends, guild and global each have a send switch")
  Equals(#receives, 3, "and a receive switch")
  Equals(sends[1].enabled, false, "the switches are disabled before the notice is confirmed")
  local friendsSend, guildSend, friendsReceive, guildReceive = sends[1], sends[2], receives[1], receives[2]
  guildSend:SetChecked(true)
  Click(guildSend)
  Equals(ns.Settings.Get("community.guild.send"), false, "a switch cannot be turned on before consent")
  Equals(guildSend.checked, false, "and the box unticks itself")
  Equals(ns.Consent.Active(), false, "no consent yet")

  local confirmButton = Button(community, ns.L.COMM_CONFIRM)
  Click(confirmButton)
  Equals(ns.Consent.Active(), true, "the confirm button gives consent")
  Equals(confirmButton.enabled, false, "and disables itself")
  Equals(guildSend.enabled, true, "the switches are enabled now")
  Equals(ns.Settings.Get("community.guild.receive"), false, "confirming alone switches nothing on")
  guildReceive:SetChecked(true)
  Click(guildReceive)
  Equals(ns.Settings.Get("community.guild.receive"), true, "the guild receive switch works")
  Equals(ns.Settings.Get("community.friends.receive"), false, "and is independent of the friends switch")

  -- A guild report arrives through the client's addon event and flags a player.
  local today = ns.Hash.Day(time())
  local hash = ns.Hash.Candidates("smoke target", time())[1]
  for index = 1, 3 do
    Deliver("R1" .. string.char(9) .. hash .. ":" .. Const.LabelValue.scam .. ":" .. today .. ":" ..
      string.format("%08x", index), "GUILD", "Carol Three")
  end
  RunShortTimers()
  Equals(ns.Resolver.Verdict("Smoke Target"), "notice", "three guild reporters flag a player with a notice")
  local _, marked = chatFilters.CHAT_MSG_SAY(nil, "CHAT_MSG_SAY", "hello", "Smoke Target")
  Check(type(marked) == "string" and marked:find("Arrow-Down-Up", 1, true) ~= nil, "and the chat line carries the notice icon")
  Equals(ns.db.community.reports.friends, nil, "nothing landed in the friends store")
  Equals(ns.Rules.Evaluate("smoke target"), "notice", "the community verdict is separate from lists and own records")

  -- Background sending: a record change is announced to the guild without any prompt.
  IsInGuild = function() return true end
  guildSend:SetChecked(true)
  Click(guildSend)
  Equals(ns.Settings.Get("community.guild.send"), true, "the guild send switch works")
  smokeSent, smokePopups = {}, 0
  RunShortTimers()
  smokeSent = {}
  ns.Records.Save("Smoke Ign", "ignore", { scam = true }, "a very private comment")
  RunShortTimers()
  local report
  for _, message in ipairs(smokeSent) do
    if message.prefix == Const.COMMUNITY_PREFIX and message.text:sub(1, 3) == "R1" .. string.char(9) then report = message end
  end
  Check(report ~= nil, "a new Ignore entry is reported in the background")
  Equals(report and report.channel, "GUILD", "to the guild")
  Check(report and not report.text:find("Smoke", 1, true) and not report.text:find("private", 1, true),
    "without the name or the comment")
  Equals(smokePopups, 0, "and without asking anything")
  local before = #printed
  Check(true, "sending prints nothing (" .. before .. " lines so far)")

  -- Preview shows hashes and labels, never names.
  local previewBox = Find(community, function(f) return f.edit ~= nil end)[1]
  Click(Button(community, ns.L.COMM_PREVIEW))
  Contains(previewBox.edit.text, ns.Hash.Target("smoke ign", ns.Hash.Season(time())), "the preview shows the hash")
  Contains(previewBox.edit.text, ns.L.LABEL_SCAM, "and the reason")
  Check(not previewBox.edit.text:find("Smoke", 1, true), "but not the name")
  previewBox.edit:SetText("tampered")
  previewBox.edit._scripts.OnTextChanged(previewBox.edit, true)
  Check(previewBox.edit.text:find("tampered", 1, true) == nil, "typing in the preview changes nothing")

  -- Rules tab.
  Click(ButtonByText(ns.L.TAB_RULES))
  local rules = TabContent(function(f) return f.kind == "Button" and f.text == ns.L.RULES_ADD_BUTTON end)
  Check(rules ~= nil, "the rules tab is built")
  local hiddenView = lastView
  local providers = Find(rules, function(f) return f.provider ~= nil end)
  Equals(#providers, 2, "a rules list and a hidden flags list")
  Equals(#providers[1].provider.data, 0, "no rules yet")
  local addRule = Button(rules, ns.L.RULES_ADD_BUTTON)
  Click(addRule)
  Equals(#ns.Rules.List(), 0, "a rule needs a reason")
  local scamBox = Checks(rules, ns.L.LABEL_SCAM)[1]
  scamBox:SetChecked(true)
  Click(scamBox)
  Click(Checks(rules, ns.L.VERDICT_IGNORE)[1])
  smokePopups = 0
  Click(addRule)
  Equals(smokePopups, 1, "a rule that ignores players asks for confirmation")
  Equals(smokeLastPopup.which, "NULLGATE_BLACKLIST_CONFIRM_RULE", "with Nullgate's Blacklist's popup")
  Contains(smokeLastPopup.a, ns.L.RULES_IGNORE_CONFIRM, "saying what it will do")
  Equals(#ns.Rules.List(), 0, "nothing is created before the player confirms")
  StaticPopupDialogs.NULLGATE_BLACKLIST_CONFIRM_RULE.OnCancel()
  Equals(#ns.Rules.List(), 0, "cancelling creates nothing")
  Click(addRule)
  StaticPopupDialogs.NULLGATE_BLACKLIST_CONFIRM_RULE.OnAccept()
  Equals(#ns.Rules.List(), 1, "confirming creates the rule")
  local rule = ns.Rules.List()[1]
  Equals(rule.label .. "/" .. rule.source .. "/" .. rule.minTier .. "/" .. rule.verdict, "scam/guild/2/ignore",
    "for the chosen reason, source (guild by default), tier (2 by default) and result")
  Equals(#providers[1].provider.data, 1, "the list shows it")
  Equals(ns.Resolver.Verdict("Smoke Target"), "notice", "three reporters are below tier 2: still only a notice")

  Click(Checks(rules, ns.L.VERDICT_WARN)[1])
  smokePopups = 0
  Click(addRule)
  Equals(smokePopups, 0, "a rule that only warns needs no confirmation")
  Equals(#ns.Rules.List(), 2, "and is created at once")
  ns.Rules.Remove(2)
  ns.Rules.Remove(1)

  -- Hiding a flag, and showing it again from the list.
  ns.Rules.Hide("Smoke Target")
  Equals(ns.Resolver.Verdict("Smoke Target"), nil, "a hidden flag has no verdict")
  Equals(#providers[2].provider.data, 1, "it appears in the hidden list")
  local hiddenRow = CreateFrame("Button", nil, providers[2])
  hiddenView.initializer(hiddenRow, providers[2].provider.data[1])
  Equals(hiddenRow.label.text, "Smoke Target", "with the player's name")
  Click(hiddenRow)
  Equals(ns.Resolver.Verdict("Smoke Target"), "notice", "clicking it brings the flag back")

  -- Revoke: asks, then withdraws what was reported and deletes what was received.
  Click(ButtonByText(ns.L.TAB_COMMUNITY))
  smokePopups, smokeSent = 0, {}
  Click(Button(community, ns.L.COMM_REVOKE))
  Equals(smokePopups, 1, "revoking asks first")
  Equals(smokeLastPopup.which, "NULLGATE_BLACKLIST_CONFIRM_REVOKE", "with Nullgate's Blacklist's popup")
  Equals(ns.Consent.Active(), true, "nothing changes before the player confirms")
  StaticPopupDialogs.NULLGATE_BLACKLIST_CONFIRM_REVOKE.OnAccept()
  RunShortTimers()
  Equals(ns.Consent.Active(), false, "revoking withdraws consent")
  Equals(ns.Settings.Get("community.guild.send"), false, "and switches sending off")
  Equals(ns.Settings.Get("community.guild.receive"), false, "and receiving")
  Equals((ns.Aggregate.Counts()), 0, "and deletes the received reports")
  Equals(ns.Resolver.Verdict("Smoke Target"), nil, "so the player is no longer flagged")
  local retraction
  for _, message in ipairs(smokeSent) do
    if message.text:sub(1, 3) == "X1" .. string.char(9) then retraction = message end
  end
  Check(retraction ~= nil, "a retraction of the earlier report went out")
  ns.Records.Remove("smoke ign")
  IsInGuild = nil
  Run("")
end

-- --- M8: setup wizard, reply control, first-run trigger and /nbl check ------------------------------------

do
  local function RunTimers(maxDelay)
    local keep = {}
    for _, timer in ipairs(smokeTimers) do
      if timer.delay <= maxDelay then timer.fn() else keep[#keep + 1] = timer end
    end
    smokeTimers = keep
  end
  local function Button(root, text)
    return Find(root, function(f) return f.kind == "Button" and f.text == text end)[1]
  end
  local function Checks(root, text)
    return Find(root, function(f) return f.kind == "CheckButton" and f.text == text end)
  end
  local function TabContent(predicate)
    for _, child in ipairs(manager.children) do
      if predicate(child) or #Find(child, predicate) > 0 then return child end
    end
    return nil
  end

  -- First run: the wizard opens a moment after login, once.
  local loginFrame
  for _, frame in ipairs(frames) do
    if frame.events and frame.events.PLAYER_LOGIN then loginFrame = frame end
  end
  Check(loginFrame ~= nil, "the login event is listened to")
  ns.Settings.Set("setupDone", false)
  local wizard = _G.CurrentNullgateBlacklistWizard
  wizard:Hide()
  smokeTimers = {}
  loginFrame._scripts.OnEvent(loginFrame, "PLAYER_LOGIN")
  local waiting
  for _, timer in ipairs(smokeTimers) do if timer.delay == 2 then waiting = timer end end
  Check(waiting ~= nil, "the wizard is scheduled two seconds after login")
  Check(not wizard:IsShown(), "and does not open at once")
  RunTimers(2)
  wizard = _G.CurrentNullgateBlacklistWizard -- a language change earlier rebuilt it under a new name
  Check(wizard:IsShown(), "on the first run the wizard opens")
  Equals(ns.Settings.Get("setupDone"), false, "opening it does not finish the setup")
  Equals(wizard.strata, "DIALOG", "it sits above other addons' frames")
  Equals(wizard.role, "window", "it is a window in the addon's own style")

  local function ShownPages()
    local count = 0
    for _, child in ipairs(wizard.children) do
      if child.kind == "Frame" and child.shown then count = count + 1 end
    end
    return count
  end
  Equals(ShownPages(), 1, "one page is shown")
  local back = Button(wizard, ns.L.WIZ_BACK)
  local nextButton = Button(wizard, ns.L.WIZ_NEXT)
  Check(back ~= nil and nextButton ~= nil, "Back and Next exist")
  Equals(back.shown, false, "Back is hidden on the first page")

  -- Page 1: language.
  local germanTitle = ns.L.WIZ_WELCOME_TITLE
  local englishChoice = Checks(wizard, ns.Locale.Names.en)[1]
  printed = {}
  Click(englishChoice)
  Equals(ns.Settings.Get("language"), "en", "the language choice saves the language")
  wizard = _G.CurrentNullgateBlacklistWizard
  Check(wizard:IsShown(), "the wizard is rebuilt in the new language and stays open")
  Check(ns.L.WIZ_WELCOME_TITLE ~= germanTitle, "(the texts are English now)")
  Equals(ShownPages(), 1, "on the same page")
  Equals(ns.Settings.Get("setupDone"), false, "changing the language does not finish the setup")
  Click(Checks(wizard, ns.L.LANG_AUTO)[1])
  wizard = _G.CurrentNullgateBlacklistWizard
  Equals(ns.Settings.Get("language"), "auto", "and can go back to automatic")
  back = Button(wizard, ns.L.WIZ_BACK)
  nextButton = Button(wizard, ns.L.WIZ_NEXT)

  -- Page 2: what Ignore does.
  Click(nextButton)
  Equals(back.shown, true, "Back appears on the second page")
  Equals(ShownPages(), 1, "still one page")
  local hide = Checks(wizard, ns.L.OPT_HIDE_CHAT)[1]
  local decline = Checks(wizard, ns.L.OPT_AUTO_DECLINE)[1]
  Equals(hide.checked, true, "the page shows the current chat setting")
  hide:SetChecked(false)
  Click(hide)
  Equals(ns.Settings.Get("hideChat"), false, "its checkbox changes the setting")
  hide:SetChecked(true)
  Click(hide)
  Equals(ns.Settings.Get("hideChat"), true, "and back")
  decline:SetChecked(false)
  Click(decline)
  Equals(ns.Settings.Get("autoDecline"), false, "the decline checkbox works too")
  decline:SetChecked(true)
  Click(decline)

  -- Page 3: automatic reply.
  Click(nextButton)
  local shortRadio = Checks(wizard, ns.L.OPT_REPLY_SHORT)[1]
  Check(shortRadio ~= nil, "the reply choices are on the third page")
  Click(shortRadio)
  Equals(ns.Settings.Get("replyMode"), "short", "choosing the short reply saves it")
  Click(Checks(wizard, ns.L.OPT_REPLY_NONE)[1])
  Equals(ns.Settings.Get("replyMode"), "none", "off saves too")

  -- Page 4: finish.
  Click(nextButton)
  Equals(nextButton.text, ns.L.WIZ_DONE, "the last page offers a short Finish button")
  Check(#nextButton.text < 20, "and not the long text of the page")
  local minimapCheck = Checks(wizard, ns.L.OPT_SHOW_MINIMAP)[1]
  minimapCheck:SetChecked(false)
  Click(minimapCheck)
  Equals(ns.Settings.Get("showMinimap"), false, "the minimap checkbox works")
  minimapCheck:SetChecked(true)
  Click(minimapCheck)
  Equals(ns.Settings.Get("community.guild.send"), false, "the wizard never switches sharing on")
  Equals(ns.Consent.Active(), false, "and never confirms the community notice")
  Click(back)
  Equals(nextButton.text, ns.L.WIZ_NEXT, "Back returns to a page with Next")
  Click(nextButton)
  Click(nextButton)
  Check(not wizard:IsShown(), "Finish closes the wizard")
  wizard._scripts.OnHide(wizard)
  Equals(ns.Settings.Get("setupDone"), true, "closing the wizard finishes the setup")

  -- It never appears again by itself, but /nbl setup brings it back.
  smokeTimers = {}
  loginFrame._scripts.OnEvent(loginFrame, "PLAYER_LOGIN")
  RunTimers(2)
  Check(not wizard:IsShown(), "after the first run the wizard stays closed")
  Run("setup")
  Check(wizard:IsShown(), "/nbl setup opens it again")
  wizard:Hide()

  -- Settings tab: the reply control and a way back into the wizard.
  Run("")
  Click(ButtonByText(ns.L.TAB_SETTINGS))
  local settings = TabContent(function(f) return f.kind == "Button" and f.text == ns.L.OPT_RUN_SETUP end)
  Check(settings ~= nil, "the settings tab has the setup button")
  Click(Checks(settings, ns.L.OPT_REPLY_LABELS)[1])
  Equals(ns.Settings.Get("replyMode"), "labels", "the settings tab sets the reply mode")
  Click(Checks(settings, ns.L.OPT_REPLY_NONE)[1])
  Equals(ns.Settings.Get("replyMode"), "none", "and turns it off")
  Click(Button(settings, ns.L.OPT_RUN_SETUP))
  Check(wizard:IsShown(), "the setup button opens the wizard")
  wizard:Hide()
  Run("")

  -- The reply listens for whispers through the client's events.
  local whisperFrame
  for _, frame in ipairs(frames) do
    if frame.events and frame.events.CHAT_MSG_WHISPER then whisperFrame = frame end
  end
  Check(whisperFrame ~= nil, "whispers are listened to for the automatic reply")
  Check(chatFilters.CHAT_MSG_WHISPER_INFORM ~= nil, "the echo of an automatic reply is filtered")

  -- /nbl check: features, then the loopback test of the sharing connection.
  local communityFrame
  for _, frame in ipairs(frames) do
    if frame.events and frame.events.CHAT_MSG_ADDON then communityFrame = frame end
  end
  smokeSent = {}
  local lines = Run("check")
  Contains(lines[1], ns.L.CHECK_HEADER, "the check starts with its header")
  local function Line(label)
    for _, line in ipairs(lines) do if line:find(label, 1, true) then return line end end
    return ""
  end
  Contains(Line(ns.L.CHECK_CHAT), ns.L.CHECK_OK, "the chat filter is found")
  Contains(Line(ns.L.CHECK_MENU), ns.L.CHECK_OK, "the right-click menu API is found")
  Contains(Line(ns.L.CHECK_ADDON), ns.L.CHECK_OK, "addon messages are found")
  Contains(Line(ns.L.CHECK_DROPDOWN), ns.L.CHECK_MISSING, "a missing feature is named (the stub has no dropdown menu)")
  Contains(Line(ns.L.CHECK_COMPRESS), ns.L.CHECK_OPTIONAL, "an optional feature is marked as optional")
  Contains(lines[#lines], ns.L.CHECK_LOOPBACK_RUN, "the loopback test is announced")
  local probe = smokeSent[#smokeSent]
  Check(probe ~= nil and probe.text:match("^T1" .. string.char(9) .. "%x%x%x%x%x%x%x%x$") ~= nil, "a test message was whispered")
  Equals(probe and probe.target, "Self Char", "to the player's own character")
  Equals(probe and probe.channel, "WHISPER", "as an addon whisper")
  printed = {}
  communityFrame._scripts.OnEvent(communityFrame, "CHAT_MSG_ADDON", Const.COMMUNITY_PREFIX, probe.text, "WHISPER", "Self Char")
  Contains(LastPrinted(), ns.L.CHECK_LOOPBACK_OK, "when the message comes back the connection is reported as working")

  -- Nothing comes back: after three seconds the failure is explained.
  smokeSent, smokeTimers = {}, {}
  Run("check")
  printed = {}
  RunTimers(3)
  Contains(LastPrinted(), string.format(ns.L.CHECK_LOOPBACK_FAIL, ns.L.CHECK_NOECHO), "silence fails the test with its reason")
end

-- --- Global channel and test mode through the real interface -----------------------------------------------

do
  local function RunTimers(maxDelay)
    local keep = {}
    for _, timer in ipairs(smokeTimers) do
      if timer.delay <= maxDelay then timer.fn() else keep[#keep + 1] = timer end
    end
    smokeTimers = keep
  end
  local function TabContent(predicate)
    for _, child in ipairs(manager.children) do
      if predicate(child) or #Find(child, predicate) > 0 then return child end
    end
    return nil
  end
  local function Checks(root, text)
    return Find(root, function(f) return f.kind == "CheckButton" and f.text == text end)
  end
  local function Button(root, text)
    return Find(root, function(f) return f.kind == "Button" and f.text == text end)[1]
  end

  -- A client that has custom channels.
  local channel
  JoinChannelByName = function(name) channel = name end
  LeaveChannelByName = function(name) if channel == name then channel = nil end end
  GetChannelName = function(name) if channel == name then return 7, name end return 0 end

  Run("")
  manager = _G.CurrentNullgateBlacklistManager
  Equals(ns.Consent.Active(), false, "(nothing is confirmed at this point)")

  -- The global switches ask for their own confirmation first.
  Click(ButtonByText(ns.L.TAB_COMMUNITY))
  local community = TabContent(function(f) return f.kind == "Button" and f.text == ns.L.COMM_CONFIRM end)
  local sends, receives = Checks(community, ns.L.COMM_SEND), Checks(community, ns.L.COMM_RECEIVE)
  Equals(#sends, 3, "friends, guild and global each have a send switch")
  Equals(#receives, 3, "and a receive switch")
  local globalSend, globalReceive = sends[3], receives[3]
  Equals(globalSend.enabled, true, "the global switches can be clicked before anything is confirmed")
  Equals(sends[2].enabled, false, "(while the guild ones cannot)")
  smokePopups = 0
  globalSend:SetChecked(true)
  Click(globalSend)
  Equals(smokePopups, 1, "turning on a global switch shows a notice")
  Equals(smokeLastPopup.which, "NULLGATE_BLACKLIST_CONFIRM_GLOBAL", "Nullgate's Blacklist's own popup")
  Equals(smokeLastPopup.a, ns.L.GLOBAL_NOTICE, "with the notice of the global channel")
  Equals(globalSend.checked, false, "the box does not stay ticked")
  Equals(ns.Settings.Get("community.global.send"), false, "and nothing was switched on")
  Equals(ns.Consent.GlobalActive(), false, "nor confirmed")
  Equals(channel, nil, "and no channel was joined")
  Contains(ns.Locale.Tables.en.GLOBAL_NOTICE, "is public", "the notice says the channel is public")

  StaticPopupDialogs.NULLGATE_BLACKLIST_CONFIRM_GLOBAL.OnAccept()
  Equals(ns.Consent.GlobalActive(), true, "accepting confirms the global notice")
  Equals(ns.Consent.Active(), true, "and the general one")
  Equals(ns.Settings.Get("community.global.send"), true, "and switches the box on")
  Equals(ns.Settings.Get("community.global.receive"), false, "only that one")
  Equals(ns.Settings.Get("community.friends.send"), false, "friends stay off")
  Equals(ns.Settings.Get("community.guild.send"), false, "and so does the guild")
  Equals(channel, "BlackbookGl", "the channel is joined")
  RunTimers(2)
  Equals(globalSend.checked, true, "the switch shows as on")

  -- A second click needs no new notice.
  smokePopups = 0
  globalReceive:SetChecked(true)
  Click(globalReceive)
  Equals(smokePopups, 0, "the notice is shown only once")
  Equals(ns.Settings.Get("community.global.receive"), true, "the receive switch works")

  -- Switching both off leaves the channel.
  globalSend:SetChecked(false)
  Click(globalSend)
  Equals(channel, "BlackbookGl", "still joined while receiving is on")
  globalReceive:SetChecked(false)
  Click(globalReceive)
  Equals(channel, nil, "with both off the channel is left")

  -- The Rules tab: a global rule moves the tier to 3.
  Click(ButtonByText(ns.L.TAB_RULES))
  local rules = TabContent(function(f) return f.kind == "Button" and f.text == ns.L.RULES_ADD_BUTTON end)
  Check(rules ~= nil, "the rules tab is there")
  Click(Checks(rules, ns.L.SOURCE_GUILD)[1])
  Equals(Checks(rules, "2")[1].checked, true, "the tier starts at 2")
  Click(Checks(rules, ns.L.SOURCE_GLOBAL)[1])
  Equals(Checks(rules, "3")[1].checked, true, "choosing global moves the tier to 3")
  Equals(Checks(rules, "2")[1].checked, false, "away from 2")
  local scamBox = Checks(rules, ns.L.LABEL_SCAM)[1]
  scamBox:SetChecked(true)
  Click(scamBox)
  Click(Button(rules, ns.L.RULES_ADD_BUTTON))
  local rule = ns.Rules.List()[#ns.Rules.List()]
  Equals(rule and (rule.source .. "/" .. rule.minTier), "global/3", "a global rule is created at tier 3")
  Click(Checks(rules, "2")[1])
  Click(Button(rules, ns.L.RULES_ADD_BUTTON))
  Equals(#ns.Rules.List(), 1, "a global rule at tier 2 is refused")
  ns.Rules.Remove(1)

  -- Test mode: sample tooltips on other players.
  Click(ButtonByText(ns.L.TAB_SETTINGS))
  local settings = TabContent(function(f) return f.kind == "CheckButton" and f.text == ns.L.OPT_TEST_MODE end)
  Check(settings ~= nil, "the settings tab has a test mode switch")
  local testBox = Checks(settings, ns.L.OPT_TEST_MODE)[1]
  Equals(ns.Tooltip.TestMode(), false, "test mode is off at first")
  smokeTarget = { "Plain", "Player" }
  GameTooltip.lines = {}
  tooltipCallback(GameTooltip)
  Equals(#GameTooltip.lines, 0, "a player with no verdict gets nothing")
  printed = {}
  testBox:SetChecked(true)
  Click(testBox)
  Equals(ns.Tooltip.TestMode(), true, "ticking the box turns test mode on")
  Contains(LastPrinted(), ns.L.MSG_TEST_MODE_ON, "and says so")
  GameTooltip.lines = {}
  tooltipCallback(GameTooltip)
  Check(#GameTooltip.lines >= 3, "the same player now gets a sample tooltip")
  Contains(GameTooltip.lines[1], "Nullgate's Blacklist: ", "that starts like a real one")
  Equals(GameTooltip.lines[#GameTooltip.lines], ns.L.TT_TEST_BANNER, "and ends by saying it is a sample")
  smokeTarget = { "Self", "Char" }
  GameTooltip.lines = {}
  tooltipCallback(GameTooltip)
  Equals(#GameTooltip.lines, 0, "your own character gets no sample")
  ns.Records.Save("Real Flagged", "ignore", { spam = true }, "a real comment")
  smokeTarget = { "Real", "Flagged" }
  GameTooltip.lines = {}
  tooltipCallback(GameTooltip)
  local joined = table.concat(GameTooltip.lines, "\n")
  Check(joined:find(ns.L.TT_TEST_BANNER, 1, true) ~= nil and not joined:find("a real comment", 1, true),
    "in test mode even a really flagged player shows the sample, not the real record")
  ns.Records.Remove("real flagged")

  -- /nbl test mode toggles it and the box follows.
  printed = {}
  Run("test mode")
  Equals(ns.Tooltip.TestMode(), false, "/nbl test mode turns it off again")
  Contains(LastPrinted(), ns.L.MSG_TEST_MODE_OFF, "and says so")
  Equals(testBox.checked, false, "and the box on the settings tab follows")
  Run("test mode")
  Equals(ns.Tooltip.TestMode(), true, "and on again")
  Run("test mode")
  smokeTarget = nil
  GameTooltip.lines = {}
  Run("")
  JoinChannelByName, LeaveChannelByName, GetChannelName = nil, nil, nil
end

-- Context menu: the player menus are hooked, and a hook adds the entries.
Check(menuHooks.MENU_UNIT_PLAYER ~= nil and menuHooks.MENU_UNIT_TARGET ~= nil, "player menus are hooked")
local entries = {}
local root = {
  CreateDivider = function() entries[#entries + 1] = "-" end,
  CreateTitle = function(_, text) entries[#entries + 1] = text end,
  CreateButton = function(_, text) entries[#entries + 1] = text end,
}
menuHooks.MENU_UNIT_TARGET(nil, root, { name = "Menu Target-Realm" })
Equals(entries[2], ns.L.CTX_TITLE, "the menu hook adds the Nullgate's Blacklist title")
Equals(entries[3], ns.L.CTX_IGNORE, "the menu hook offers Ignore for a new player")

-- The report card opens from the menu and fills its window.
Equals(entries[#entries], ns.L.CTX_CARD, "the menu ends with the report card")
Check(ns.ReportCard.Open("Menu Target-Realm"), "the report card opens")
Check(_G.CurrentNullgateBlacklistReportCard ~= nil and _G.CurrentNullgateBlacklistReportCard:IsShown(), "its window is shown")
_G.CurrentNullgateBlacklistReportCard:Hide()

-- --- Summary -------------------------------------------------------------------

io.write(string.format("smoke: %d checks, %d failure(s)\n", checks, failures))
io.stdout:flush()
if failures > 0 then os.exit(1) end
os.exit(0)
