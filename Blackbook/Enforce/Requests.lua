-- Blackbook: auto-decline of invites, duels and trades from ignored players
-- (section 6.4). Every client call is looked up at call time and guarded, so a
-- missing API disables only that one decline.
local _, ns = ...

local Identity = ns.Identity
local Settings = ns.Settings
local Resolver = ns.Resolver
local Output = ns.Output

local Requests = {}
ns.Requests = Requests

-- One rule per event. who() returns the other player's normalized name from
-- the event arguments; decline is the global function that refuses; popup is
-- the static popup to hide (nil when there is none).
local RULES = {
  PARTY_INVITE_REQUEST = {
    kind = "REQ_PARTY", decline = "DeclineGroup", popup = "PARTY_INVITE",
    who = function(inviter) return Identity.Normalize(inviter) end,
  },
  GUILD_INVITE_REQUEST = {
    kind = "REQ_GUILD", decline = "DeclineGuild", popup = "GUILD_INVITE",
    who = function(inviter) return Identity.Normalize(inviter) end,
  },
  DUEL_REQUESTED = {
    kind = "REQ_DUEL", decline = "CancelDuel", popup = "DUEL_REQUESTED",
    who = function(challenger) return Identity.Normalize(challenger) end,
  },
  TRADE_SHOW = {
    kind = "REQ_TRADE", decline = "CancelTrade",
    who = function() return Identity.FromUnit("npc") end,
  },
}

local function CallGlobal(name, ...)
  local fn = _G[name]
  if type(fn) == "function" then pcall(fn, ...) end
end

-- Handles one event. Returns true when the request was declined.
function Requests.Handle(event, ...)
  local rule = RULES[event]
  if not rule then return false end
  if not Settings.Get("autoDecline") then return false end
  local name = rule.who(...)
  if not name then return false end
  if Resolver.Verdict(name) ~= "ignore" then return false end

  CallGlobal(rule.decline)
  if rule.popup then CallGlobal("StaticPopup_Hide", rule.popup) end
  if Settings.Get("showNotices") then
    Output.Print(string.format(Output.Text("MSG_DECLINED"),
      Output.Text(rule.kind), Output.Escape(name)))
  end
  return true
end

local registered = false

-- Starts listening for the request events. Returns false without frames.
function Requests.Register()
  if registered then return true end
  if type(CreateFrame) ~= "function" then return false end
  local frame = CreateFrame("Frame")
  for event in pairs(RULES) do
    frame:RegisterEvent(event)
  end
  frame:SetScript("OnEvent", function(_, event, ...)
    Requests.Handle(event, ...)
  end)
  registered = true
  return true
end
