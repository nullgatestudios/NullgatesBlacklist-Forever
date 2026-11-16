-- Blackbook: "/bb check". Reports which client features Blackbook relies on
-- exist in this client, then whispers an addon message to the player's own
-- character to prove that the sharing transport works end to end. It needs no
-- other player and changes nothing.
local _, ns = ...

local Output = ns.Output
local Widgets = ns.Widgets

local Text, Print = Output.Text, Output.Print

local Check = {}
ns.Check = Check

local GREEN, RED, GRAY = "|cff66ff66", "|cffff6666", "|cffaaaaaa"

local function Has(value) return type(value) == "function" end

-- A frame of this template can be created in this client (and is thrown away).
local function CanCreate(kind, template)
  local frame = Widgets.Create(kind, template, UIParent)
  if not frame then return false, nil end
  if Has(frame.Hide) then frame:Hide() end
  return true, frame
end

-- { label key, test function, optional }
local TESTS = {
  { "CHECK_CHAT", function()
    return Has(ChatFrame_AddMessageEventFilter) or (ChatFrameUtil ~= nil and Has(ChatFrameUtil.AddMessageEventFilter))
  end },
  { "CHECK_MENU", function() return Menu ~= nil and Has(Menu.ModifyMenu) end },
  { "CHECK_TOOLTIP", function()
    return TooltipDataProcessor ~= nil and Has(TooltipDataProcessor.AddTooltipPostCall)
  end },
  { "CHECK_LIST", function()
    return Has(CreateScrollBoxListLinearView) and Has(CreateDataProvider)
      and ScrollUtil ~= nil and Has(ScrollUtil.InitScrollBoxListWithScrollBar)
      and (CanCreate("Frame", "WowScrollBoxList"))
  end },
  { "CHECK_DROPDOWN", function()
    local ok, frame = CanCreate("DropdownButton", "WowStyle1DropdownTemplate")
    return ok and frame ~= nil and Has(frame.SetupMenu) and MenuResponse ~= nil
  end },
  { "CHECK_SCROLL", function() return (CanCreate("ScrollFrame", "UIPanelScrollFrameTemplate")) end },
  { "CHECK_POPUP", function() return type(StaticPopupDialogs) == "table" and Has(StaticPopup_Show) end },
  { "CHECK_ADDON", function()
    local api = C_ChatInfo
    return (api ~= nil and Has(api.SendAddonMessage) and Has(api.RegisterAddonMessagePrefix))
      or (Has(SendAddonMessage) and Has(RegisterAddonMessagePrefix))
  end },
  { "CHECK_FRIENDS", function()
    return C_FriendList ~= nil and Has(C_FriendList.GetNumFriends) and Has(C_FriendList.GetFriendInfoByIndex)
  end },
  { "CHECK_GUILD", function() return Has(IsInGuild) end },
  { "CHECK_TIMER", function() return C_Timer ~= nil and Has(C_Timer.After) end },
  { "CHECK_COMPRESS", function()
    return C_EncodingUtil ~= nil and Has(C_EncodingUtil.CompressString) and Has(C_EncodingUtil.DecompressString)
  end, true },
}

-- Runs the feature checks, prints one line each and returns how many required
-- features are missing.
function Check.Features()
  local missing = 0
  for _, test in ipairs(TESTS) do
    local label, run, optional = test[1], test[2], test[3]
    local ok, result = pcall(run)
    ok = ok and result and true or false
    local verdict
    if ok then
      verdict = GREEN .. Text("CHECK_OK") .. "|r"
    elseif optional then
      verdict = GRAY .. Text("CHECK_OPTIONAL") .. "|r"
    else
      verdict = RED .. Text("CHECK_MISSING") .. "|r"
      missing = missing + 1
    end
    Print(string.format(Text("CHECK_LINE"), Text(label), verdict))
  end
  return missing
end

-- The whole command: the feature list, then the loopback test of the sharing
-- connection, whose result is printed when it is known.
function Check.Run()
  Print(Text("CHECK_HEADER"))
  Check.Features()
  Print(Text("CHECK_LOOPBACK_RUN"))
  ns.Net.SelfTest(function(ok, reason)
    if ok then
      Print(GREEN .. Text("CHECK_LOOPBACK_OK") .. "|r")
    else
      local why = Text(reason == "refused" and "CHECK_REFUSED" or "CHECK_NOECHO")
      Print(RED .. string.format(Text("CHECK_LOOPBACK_FAIL"), why) .. "|r")
    end
  end)
end
