-- Blackbook: opt-in for community sharing (section 8.9). Everything is off
-- until the player confirms the disclosure; each source has its own send and
-- receive switch, and "revoke" stops sharing and wipes what was received.
--
-- The disclosure has a version number. If the text changes, the version is
-- raised and every switch stops working until it is confirmed again.
local _, ns = ...

local Const = ns.Const
local Events = ns.Events
local Settings = ns.Settings

local Consent = {}
ns.Consent = Consent

-- Sources that can be switched on in this version. "global" arrives with M9 and
-- stays off and untouchable until then.
local AVAILABLE = { friends = true, guild = true }

function Consent.Active()
  return Settings.Get("community.consentVersion") == Const.ConsentVersion
end

-- True when the player confirmed the disclosure and switched this on.
-- direction is "send" or "receive".
function Consent.Allows(source, direction)
  if not AVAILABLE[source] or (direction ~= "send" and direction ~= "receive") then return false end
  return Consent.Active() and Settings.Get("community." .. source .. "." .. direction) == true
end

-- The sources the player receives from, in a fixed order.
function Consent.Receiving()
  local list = {}
  for _, source in ipairs(Const.Sources) do
    if Consent.Allows(source, "receive") then list[#list + 1] = source end
  end
  return list
end

-- The sources the player sends to.
function Consent.Sending()
  local list = {}
  for _, source in ipairs(Const.Sources) do
    if Consent.Allows(source, "send") then list[#list + 1] = source end
  end
  return list
end

function Consent.Confirm()
  Settings.Set("community.consentVersion", Const.ConsentVersion)
  Events:Fire(Const.Events.COMMUNITY_CHANGED)
end

-- Switches one direction of one source. Refused (false) before the disclosure
-- is confirmed, and for a source that is not available yet.
function Consent.SetToggle(source, direction, value)
  if not AVAILABLE[source] or (direction ~= "send" and direction ~= "receive") then return false end
  if value and not Consent.Active() then return false end
  Settings.Set("community." .. source .. "." .. direction, value and true or false)
  Events:Fire(Const.Events.COMMUNITY_CHANGED)
  return true
end

-- Stops all sharing, retracts what was reported where possible and deletes every
-- received report. The player's rules and own list stay.
function Consent.Revoke()
  if ns.Net and type(ns.Net.RetractAll) == "function" then ns.Net.RetractAll() end
  for source in pairs(AVAILABLE) do
    Settings.Set("community." .. source .. ".send", false)
    Settings.Set("community." .. source .. ".receive", false)
  end
  Settings.Set("community.consentVersion", 0)
  ns.Aggregate.Purge()
  if ns.db and ns.db.community then ns.db.community.sent = {} end
  Events:Fire(Const.Events.COMMUNITY_CHANGED)
end
