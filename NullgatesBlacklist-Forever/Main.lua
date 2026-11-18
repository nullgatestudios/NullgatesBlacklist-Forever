-- Nullgate's Blacklist: ADDON_LOADED bootstrap and slash commands (sections 4.1, 6.5).
local addonName, ns = ...

local Const = ns.Const

local Text, Escape, Print = ns.Output.Text, ns.Output.Escape, ns.Output.Print

local function VerdictText(verdict)
  return Text("VERDICT_" .. string.upper(tostring(verdict or "")))
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

local function ToggleManager()
  if ns.Manager and type(ns.Manager.Toggle) == "function" then
    ns.Manager.Toggle()
  else
    Print(Text("MSG_NO_MANAGER"))
  end
end

local function SetLanguage(value)
  local choice = ns.Locale.Set(string.lower(value or ""))
  if not choice then
    local codes = { "auto" }
    for _, entry in ipairs(ns.Locale.List()) do codes[#codes + 1] = entry.code end
    Print(string.format(Text("MSG_LANG_INVALID"), table.concat(codes, ", ")))
    return
  end
  Print(string.format(Text("MSG_LANG_SET"), Escape(ns.Locale.NameOf(choice))))
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
    "HELP_TEST", "HELP_TESTMODE", "HELP_CHECK", "HELP_HELP",
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
      ns.Editor.Open(rest, command)
    end
  elseif command == "remove" then
    if rest == "" then
      Print(string.format(Text("MSG_NEED_NAME"), command))
    else
      ns.Editor.Remove(rest)
    end
  elseif command == "test" then
    local verdict = string.lower(rest)
    if verdict == "mode" then
      local on = not ns.Tooltip.TestMode()
      ns.Tooltip.SetTestMode(on)
      Print(Text(on and "MSG_TEST_MODE_ON" or "MSG_TEST_MODE_OFF"))
      ns.Manager.Refresh()
    elseif Const.VerdictRank[verdict] then
      ns.Chat.Preview(verdict)
    else
      Print(Text("MSG_TEST_USAGE"))
    end
  elseif command == "setup" then
    ns.Wizard.Open()
  elseif command == "check" then
    ns.Check.Run()
  elseif command == "minimap" then
    ns.Minimap.Toggle()
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

SLASH_NULLGATESBLACKLIST1 = Const.SLASH_LONG
SLASH_NULLGATESBLACKLIST2 = Const.SLASH_SHORT
SlashCmdList["NULLGATESBLACKLIST"] = HandleSlash

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_LOGIN")
-- Blackbook was renamed to Nullgate's Blacklist (a fresh start: its saved data is
-- not carried over). If the old folder is still installed both copies would run,
-- join the global channel and filter chat twice, so offer to disable the old one.
local OLD_ADDON = "Blackbook"
local OLD_ADDON_POPUP = "NULLGATE_BLACKLIST_OLD_ADDON"

local function OfferDisableOldAddon()
  local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
  local disable = (C_AddOns and C_AddOns.DisableAddOn) or DisableAddOn
  if type(isLoaded) ~= "function" or type(disable) ~= "function" or not isLoaded(OLD_ADDON) then return end
  if type(StaticPopupDialogs) ~= "table" or type(StaticPopup_Show) ~= "function" then return end
  StaticPopupDialogs[OLD_ADDON_POPUP] = {
    text = Text("OLD_ADDON_NOTICE"),
    button1 = Text("OLD_ADDON_DISABLE"),
    button2 = CANCEL,
    OnAccept = function()
      disable(OLD_ADDON)
      ReloadUI()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
  }
  StaticPopup_Show(OLD_ADDON_POPUP)
end

loader:SetScript("OnEvent", function(_, event, name)
  if event == "PLAYER_LOGIN" then
    -- The first-run wizard waits a moment so the interface has finished loading.
    if ns.db and type(C_Timer) == "table" then
      C_Timer.After(2, ns.Wizard.MaybeOpen)
      C_Timer.After(4, OfferDisableOldAddon)
    end
    return
  end
  if event ~= "ADDON_LOADED" or name ~= addonName then return end
  local _, state = ns.Settings.Init()
  ns.Locale.Apply()
  ns.Chat.Register()
  ns.Requests.Register()
  ns.ContextMenu.Register()
  ns.Minimap.Register()
  ns.Portrait.Register()
  ns.Tooltip.Register()
  ns.Net.Register()
  ns.Global.Register()
  ns.Reply.Register()
  if state == "newer" then Print(Text("MSG_DB_NEWER")) end
  Print(Text("MSG_LOADED"))
end)
