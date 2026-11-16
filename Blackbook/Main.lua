-- Blackbook: ADDON_LOADED bootstrap and slash commands (sections 4.1, 6.5).
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
  local choice = ns.Settings.SetLanguage(string.lower(value or ""))
  if not choice then
    Print(Text("MSG_LANG_INVALID"))
    return
  end
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
    "HELP_TEST", "HELP_HELP",
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
    if Const.VerdictRank[verdict] then
      ns.Chat.Preview(verdict)
    else
      Print(Text("MSG_TEST_USAGE"))
    end
  elseif command == "setup" then
    Print(string.format(Text("MSG_NOT_AVAILABLE"), Text("CMD_SETUP")))
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
  ns.ContextMenu.Register()
  ns.Minimap.Register()
  ns.Portrait.Register()
  ns.Tooltip.Register()
  ns.Transfer.Register()
  if state == "newer" then Print(Text("MSG_DB_NEWER")) end
  Print(Text("MSG_LOADED"))
end)
