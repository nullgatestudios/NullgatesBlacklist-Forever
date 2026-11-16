-- Blackbook: one chat filter for every channel (section 6.4). Chat from a
-- player whose verdict is "ignore" is hidden while hideChat is on. Markers for
-- warn and notice join in M5.
local _, ns = ...

local Const = ns.Const
local Safe = ns.Safe
local Identity = ns.Identity
local Settings = ns.Settings
local Resolver = ns.Resolver
local Output = ns.Output
local Markers = ns.Markers

local Chat = {}
ns.Chat = Chat

local EVENTS = {
  "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_EMOTE", "CHAT_MSG_TEXT_EMOTE",
  "CHAT_MSG_CHANNEL", "CHAT_MSG_WHISPER",
  "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
  "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING",
  "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER",
  "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER",
}

local lastNotice = {} -- target key -> time of the last whisper notice

local function Now()
  if type(GetTime) == "function" then return GetTime() end
  return time()
end

-- The game calls a filter once per chat window, so the notice needs its own
-- throttle: at most one per person per Const.WhisperNoticeSeconds.
local function NoticeWhisper(name)
  if not Settings.Get("showNotices") then return end
  local key = string.lower(name)
  local now = Now()
  local last = lastNotice[key]
  if last and now - last < Const.WhisperNoticeSeconds then return end
  lastNotice[key] = now
  Output.Print(string.format(Output.Text("MSG_WHISPER_HIDDEN"), Output.Escape(name)))
end

-- Chat filter. Returns true to hide the message. Otherwise returns false, plus
-- the message with the verdict icon in front when the author has a verdict
-- (the game passes the remaining arguments on unchanged). Secret authors or
-- texts are never touched.
function Chat.Filter(_, event, msg, author, ...)
  local text = Safe.Str(msg)
  if not text then return false end
  local name = Identity.Normalize(author)
  if not name then return false end
  local verdict = Resolver.Verdict(name)
  if not verdict then return false end
  if verdict == "ignore" and Settings.Get("hideChat") then
    if event == "CHAT_MSG_WHISPER" then NoticeWhisper(name) end
    return true
  end
  return false, Chat.Mark(verdict, text), author, ...
end

-- The text of a shown chat line for a flagged author.
function Chat.Mark(verdict, text)
  return Markers.Icon(verdict) .. " " .. text
end

-- /bb test <verdict>: prints a sample line the way the filter would show it, so
-- the icons can be checked in game without a flagged player speaking. An ignored
-- line is only shown when chat hiding is off; otherwise the real one is hidden.
function Chat.Preview(verdict)
  local sample = Output.Text("MSG_TEST_SAMPLE")
  if verdict == "ignore" and Settings.Get("hideChat") then
    Output.Print(Output.Text("MSG_TEST_HIDDEN"))
    return
  end
  local frame = DEFAULT_CHAT_FRAME
  if frame then frame:AddMessage(Chat.Mark(verdict, "[" .. Output.Text("VERDICT_" .. string.upper(verdict)) .. "] " .. sample)) end
end

-- Adds a filter function to a chat event. Returns false when the client has no
-- filter API.
function Chat.AddFilter(event, fn)
  local add = ChatFrame_AddMessageEventFilter
  if type(add) ~= "function" and ChatFrameUtil then add = ChatFrameUtil.AddMessageEventFilter end
  if type(add) ~= "function" then return false end
  add(event, fn)
  return true
end

local registered = false

-- Installs the filter on every chat event. Returns false when the client has
-- no filter API; the addon keeps running without chat hiding.
function Chat.Register()
  if registered then return true end
  for _, event in ipairs(EVENTS) do
    if not Chat.AddFilter(event, Chat.Filter) then
      Output.Print(Output.Text("MSG_NO_CHAT_FILTER"))
      return false
    end
  end
  registered = true
  return true
end

Chat.Events = EVENTS
