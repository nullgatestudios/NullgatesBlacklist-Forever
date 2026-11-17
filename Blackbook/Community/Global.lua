-- Blackbook: the global channel (section 8.10). One fixed custom channel that
-- every Blackbook user who switched global sharing on joins. It is joined only
-- while global sending or receiving is on and left again when both are off. The
-- channel carries addon messages only; nothing is written to the chat, its join
-- notices are filtered out and it is removed from the chat windows.
local _, ns = ...

local Const = ns.Const
local Safe = ns.Safe
local Consent = ns.Consent
local Events = ns.Events

local Global = {}
ns.Global = Global

Global.name = Const.GLOBAL_CHANNEL

local RETRY_SECONDS = 10
local MAX_TRIES = 4

-- The client calls this module needs. Tests replace them.
Global.io = {
  join = function(name)
    local join = JoinChannelByName or JoinTemporaryChannel
    if type(join) ~= "function" then return false end
    return (pcall(join, name))
  end,
  leave = function(name)
    if type(LeaveChannelByName) ~= "function" then return false end
    return (pcall(LeaveChannelByName, name))
  end,
  id = function(name)
    if type(GetChannelName) ~= "function" then return nil end
    local ok, id = pcall(GetChannelName, name)
    if ok and type(id) == "number" and id > 0 then return id end
    return nil
  end,
  hideFromChat = function(name)
    -- Take the channel out of every chat window so its messages never show.
    if type(ChatFrame_RemoveChannel) ~= "function" then return end
    for index = 1, (NUM_CHAT_WINDOWS or 10) do
      local frame = _G["ChatFrame" .. index]
      if frame then pcall(ChatFrame_RemoveChannel, frame, name) end
    end
  end,
  after = function(seconds, fn) C_Timer.After(seconds, fn) end,
}

-- The channel number to send on, or nil when the channel is not joined.
function Global.ChannelId()
  return Global.io.id(Global.name)
end

-- True when a channel name from an event is ours. The event gives either the bare
-- name or "5. Name".
function Global.IsOurs(channelName)
  local text = Safe.Str(channelName)
  if not text then return false end
  text = string.lower(text)
  local ours = string.lower(Global.name)
  return text == ours or text:match("^%d+%.%s*(.-)%s*$") == ours
end

-- Whether the player wants the channel: global sending or receiving is on.
function Global.Wanted()
  return Consent.Allows("global", "send") or Consent.Allows("global", "receive")
end

local tries = 0
local checking = false

local function Check()
  checking = false
  if not Global.Wanted() then return end
  if Global.ChannelId() then
    tries = 0
    Global.io.hideFromChat(Global.name)
    -- Sending waits for the channel; tell the rest of the addon it is there now.
    Events:Fire(Const.Events.COMMUNITY_CHANGED)
    return
  end
  tries = tries + 1
  if tries < MAX_TRIES then Global.Join() end
end

-- Joins the channel and checks, a little later, that it worked.
function Global.Join()
  if Global.ChannelId() then return true end
  if checking then return false end -- a join is already under way
  Global.io.join(Global.name)
  checking = true
  Global.io.after(tries == 0 and 2 or RETRY_SECONDS, Check)
  return false
end

function Global.Leave()
  tries = 0
  if Global.ChannelId() then Global.io.leave(Global.name) end
end

-- Brings the channel in line with the switches: joined while one is on, left
-- when both are off. Safe to call at any time.
function Global.Sync()
  if Global.Wanted() then
    if not Global.ChannelId() then Global.Join() end
  else
    Global.Leave()
  end
end

-- Chat filter for the channel's notices ("You joined the channel ..."): hidden.
-- The channel name sits in the fourth and the ninth event arguments.
function Global.Filter(_, _, _, _, _, channelString, _, _, _, _, baseName)
  if Global.IsOurs(channelString) or Global.IsOurs(baseName) then return true end
  return false
end

local NOTICE_EVENTS = {
  "CHAT_MSG_CHANNEL_NOTICE", "CHAT_MSG_CHANNEL_NOTICE_USER",
  "CHAT_MSG_CHANNEL_JOIN", "CHAT_MSG_CHANNEL_LEAVE",
}

local registered = false

-- Installs the notice filter, follows changes of the switches and joins the
-- channel a few seconds after the world has loaded. Returns false when the client
-- has no timers.
function Global.Register()
  if registered then return true end
  if type(CreateFrame) ~= "function" or type(C_Timer) ~= "table" then return false end
  for _, event in ipairs(NOTICE_EVENTS) do ns.Chat.AddFilter(event, Global.Filter) end
  Events:On(Const.Events.COMMUNITY_CHANGED, Global.Sync)
  local frame = CreateFrame("Frame")
  frame:RegisterEvent("PLAYER_ENTERING_WORLD")
  frame:SetScript("OnEvent", function()
    Global.io.after(5, Global.Sync)
  end)
  registered = true
  return true
end

-- Forgets what was tried (tests).
function Global.Reset()
  tries, checking = 0, false
end
