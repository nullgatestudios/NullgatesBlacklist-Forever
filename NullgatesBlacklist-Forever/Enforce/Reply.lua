-- Nullgate's Blacklist: the optional automatic reply (section 6.4). When a player you
-- ignore through an OWN record whispers you and the reply mode is on, one polite
-- reply goes out after a moment, in your language, at most once per player and
-- session. It never contains your comment. Your own outgoing reply is hidden
-- from your chat for a few seconds so you do not see a message you did not type.
local _, ns = ...

local Safe = ns.Safe
local Identity = ns.Identity
local Settings = ns.Settings
local Resolver = ns.Resolver
local Output = ns.Output
local Wire = ns.Wire
local Chat = ns.Chat

local Text, Print = Output.Text, Output.Print

local Reply = {}
ns.Reply = Reply

local DELAY = 1.5        -- seconds between the whisper and the reply
local HIDE_SECONDS = 15  -- how long the echo of our own reply is hidden
local MAX_BYTES = 250    -- a chat message is at most 255 bytes
local PREFIX_BYTES = 40  -- the echo is matched by this much of the text

-- The few client calls this module needs. Tests replace them.
Reply.io = {
  send = function(text, target)
    local api = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    if type(api) ~= "function" then return false end
    return (pcall(api, text, "WHISPER", nil, target))
  end,
  after = function(seconds, fn) C_Timer.After(seconds, fn) end,
  now = function()
    if type(GetTime) == "function" then return GetTime() end
    return time()
  end,
}

local replied = {}  -- target key -> true, for this session
local hiding = {}   -- { prefix =, untilTime = } for our own outgoing replies
local failureShown = false

-- The reply text for a mode ("short" or "labels") and a label set. The text is
-- built from the current language and never includes a comment.
function Reply.Text(mode, labels)
  local text
  if mode == "labels" then
    local names = Output.LabelText(labels)
    if names == "" then
      text = Text("REPLY_SHORT")
    else
      text = string.format(Text("REPLY_LABELS"), names)
    end
  else
    text = Text("REPLY_SHORT")
  end
  return Wire.Truncate(text, MAX_BYTES)
end

local function Hide(text)
  local now = Reply.io.now()
  local kept = {}
  for _, entry in ipairs(hiding) do
    if entry.untilTime > now then kept[#kept + 1] = entry end
  end
  kept[#kept + 1] = { prefix = text:sub(1, PREFIX_BYTES), untilTime = now + HIDE_SECONDS }
  hiding = kept
end

local function Send(name, text)
  Hide(text)
  if not Reply.io.send(text, name) and not failureShown then
    failureShown = true
    Print(Text("MSG_REPLY_FAILED"))
  end
end

-- Handles a whisper (the CHAT_MSG_WHISPER event). Only an ignore that comes from
-- an own record is answered; imported lists and community data never trigger it.
function Reply.OnWhisper(message, author)
  local mode = Settings.Get("replyMode")
  if mode ~= "short" and mode ~= "labels" then return end
  local name = Identity.Normalize(author)
  if not name or not Safe.Str(message) or Identity.Same(name, Identity.Self()) then return end
  local verdict, reasons = Resolver.Verdict(name)
  local reason = reasons and reasons[1]
  if verdict ~= "ignore" or not reason or reason.source ~= "own" then return end
  local key = Identity.Key(name)
  if replied[key] then return end
  replied[key] = true
  local text = Reply.Text(mode, reason.labels)
  Reply.io.after(DELAY, function() Send(name, text) end)
end

-- Chat filter for CHAT_MSG_WHISPER_INFORM: hides the echo of our own reply.
function Reply.Filter(_, _, message)
  local text = Safe.Str(message)
  if not text or #hiding == 0 then return false end
  local now = Reply.io.now()
  for _, entry in ipairs(hiding) do
    if entry.untilTime > now and text:sub(1, #entry.prefix) == entry.prefix then return true end
  end
  return false
end

local registered = false

-- Listens for whispers and installs the echo filter. Returns false when the
-- client lacks what is needed; everything else keeps working.
function Reply.Register()
  if registered then return true end
  if type(CreateFrame) ~= "function" or type(C_Timer) ~= "table" then return false end
  local frame = CreateFrame("Frame")
  frame:RegisterEvent("CHAT_MSG_WHISPER")
  frame:SetScript("OnEvent", function(_, _, message, author)
    Reply.OnWhisper(message, author)
  end)
  Chat.AddFilter("CHAT_MSG_WHISPER_INFORM", Reply.Filter)
  registered = true
  return true
end

-- Forgets the session state (tests).
function Reply.Reset()
  replied, hiding, failureShown = {}, {}, false
end
