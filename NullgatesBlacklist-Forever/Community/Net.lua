-- Nullgate's Blacklist: sending and receiving community reports in the background
-- (sections 8.6, 8.7 and 8.10). Nothing here prints or asks: once the player has
-- opted in, reports about their Ignore entries go out quietly to the guild, to
-- friends who run the addon and, if chosen, to the global channel, and reports
-- from those sources are filed.
--
-- Sending is one message at a time with a gap, one pending slot per target, and
-- is retried a few times. Receiving checks everything and drops silently.
-- The sender of a global message is used for the checks and never stored. For
-- friends and guild the sending character is kept with the report, so the report
-- card can show who reported a player (the consent notice says they can see this).
local _, ns = ...

local Const = ns.Const
local Safe = ns.Safe
local Identity = ns.Identity
local Settings = ns.Settings
local Events = ns.Events
local Records = ns.Records
local Hash = ns.Hash
local Report = ns.Report
local Aggregate = ns.Aggregate
local Consent = ns.Consent
local Roster = ns.Roster
local Envelope = ns.Envelope
local Global = ns.Global
local Output = ns.Output

local Net = {}
ns.Net = Net

local Limits = Const.Community
local PREFIX = Const.COMMUNITY_PREFIX
local HELLO_REPLY_SECONDS = 60
local CHANGE_DELAY = 1       -- changes are batched for this long before a sync
local MAINTENANCE = 86400    -- expiry of old reports, once a day

-- The few client calls this module needs. Tests replace them.
Net.io = {
  send = function(prefix, text, channel, target)
    local api = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage
    if type(api) ~= "function" then return false end
    local ok, result = pcall(api, prefix, text, channel, target)
    -- Newer clients return a result code (0 = sent), older ones nothing or a boolean.
    return ok and (result == nil or result == true or result == 0)
  end,
  after = function(seconds, fn) C_Timer.After(seconds, fn) end,
  now = function()
    if type(GetTime) == "function" then return GetTime() end
    return time()
  end,
  serverTime = function() return Hash.ServerTime() end,
  random = function(low, high) return math.random(low, high) end,
}

local function Key(name) return string.lower(name) end

-- --- Outbox ----------------------------------------------------------------------
-- pending[destKey] = { channel =, target =, order = { itemKey... }, items = { itemKey = item } }
-- An item is { kind = "R" | "X" | "H1" | "H2", hash =, mask =, day =, token = }.
-- A newer report for the same target replaces an unsent one; a retraction cancels
-- an unsent report for that target.

local pending, destOrder = {}, {}
local pumping = false

-- The token is part of the key, because on the global channel reports of several
-- reporters about one target wait side by side (the ones we pass on).
local function ItemKey(item)
  if item.hash then return item.kind .. item.hash .. (item.token or "") end
  return item.kind
end

-- A destination is { key =, channel =, target = } and may add resolve() (looks
-- the target up when sending), wrap(text) (the envelope) and gap (seconds to
-- wait after a message).
local function Queue(dest, item)
  local slot = pending[dest.key]
  if not slot then
    slot = { channel = dest.channel, target = dest.target, resolve = dest.resolve, wrap = dest.wrap,
      gap = dest.gap, order = {}, items = {} }
    pending[dest.key] = slot
    destOrder[#destOrder + 1] = dest.key
  end
  if item.kind == "X" then slot.items["R" .. item.hash .. (item.token or "")] = nil end
  local key = ItemKey(item)
  if slot.items[key] == nil then slot.order[#slot.order + 1] = key end
  slot.items[key] = item
end

-- Drops keys of items that were replaced or cancelled; removes empty slots.
local function Compact(destKey)
  local slot = pending[destKey]
  local kept = {}
  for _, key in ipairs(slot.order) do
    if slot.items[key] then kept[#kept + 1] = key end
  end
  slot.order = kept
  if #kept == 0 then
    pending[destKey] = nil
    for index, existing in ipairs(destOrder) do
      if existing == destKey then table.remove(destOrder, index) break end
    end
    return false
  end
  return true
end

-- The next message to send: its destination, the item keys it carries and its text.
local function NextMessage()
  for _, destKey in ipairs(destOrder) do
    if Compact(destKey) then
      local slot = pending[destKey]
      local first = slot.items[slot.order[1]]
      local keys, items = {}, {}
      local limit = (first.kind == "R" or first.kind == "X") and Limits.recordsPerMessage or 1
      for _, key in ipairs(slot.order) do
        local item = slot.items[key]
        if item.kind == first.kind and #keys < limit then
          keys[#keys + 1] = key
          items[#items + 1] = item
        end
      end
      local text
      if first.kind == "R" then
        text = Report.Messages(items)[1]
      elseif first.kind == "X" then
        text = Report.RetractMessages(items)[1]
      else
        text = first.kind
      end
      return destKey, slot, keys, text
    end
  end
  return nil
end

local function Pump()
  local destKey, slot, keys, text = NextMessage()
  if not destKey then
    pumping = false
    return
  end
  local target = slot.target
  if slot.resolve then target = slot.resolve() end
  local payload = text
  if slot.wrap then payload = slot.wrap(text) end
  local sent = false
  if payload ~= nil and (target ~= nil or not slot.resolve) then
    sent = Net.io.send(PREFIX, payload, slot.channel, target)
  end
  if sent then
    for _, key in ipairs(keys) do slot.items[key] = nil end
    -- Let the next destination go first.
    for index, existing in ipairs(destOrder) do
      if existing == destKey then
        table.remove(destOrder, index)
        destOrder[#destOrder + 1] = destKey
        break
      end
    end
    Net.io.after(slot.gap or Limits.sendGap, Pump)
  else
    for _, key in ipairs(keys) do
      local item = slot.items[key]
      item.tries = (item.tries or 0) + 1
      if item.tries >= Limits.retries then
        slot.items[key] = nil
        -- Not delivered: forget the announcement so a later sync tries again.
        if item.kind == "R" and item.class and ns.db and ns.db.community and ns.db.community.sent then
          local sentSet = ns.db.community.sent[item.class]
          if sentSet then sentSet[item.hash] = nil end
        end
      end
    end
    Net.io.after(Limits.retryDelay, Pump)
  end
end

local function Kick()
  if pumping then return end
  pumping = true
  Pump()
end

-- Messages waiting to be sent (for the Community tab and tests).
function Net.PendingCount()
  local count = 0
  for _, slot in pairs(pending) do
    for _ in pairs(slot.items) do count = count + 1 end
  end
  return count
end

-- Messages waiting for the global channel.
local function GlobalQueued()
  local slot = pending.global
  local count = 0
  if slot then
    for _ in pairs(slot.items) do count = count + 1 end
  end
  return count
end

-- --- What to send ------------------------------------------------------------------

local function Secret()
  return ns.db.community.install.secret
end

-- The reports for one class of destinations; global ones are hashed with their own salt.
local function CurrentItems(class)
  return Report.Build(Records.All(), {
    shareLabels = Settings.Get("community.shareLabels") or {},
    secret = Secret(),
    now = Net.io.serverTime(),
    group = Const.SourceGroup[class] or "friends",
  })
end

-- What has been announced to a class of destinations ("guild" or "friends"):
-- target hash -> label mask. Kept in the saved data so only changes are sent.
local function SentSet(class)
  local community = ns.db.community
  if type(community.sent) ~= "table" then community.sent = {} end
  if type(community.sent[class]) ~= "table" then community.sent[class] = {} end
  return community.sent[class]
end

local GUILD = { key = "guild", channel = "GUILD" }

-- The global channel: its number is looked up when a message is sent, the text is
-- put in the hourly envelope, and messages go out slowly because everyone listens.
local GLOBAL = {
  key = "global", channel = "CHANNEL", gap = Limits.globalGap,
  resolve = function() return Global.ChannelId() end,
  wrap = function(text) return Envelope.Encode(text, Envelope.Hour(Net.io.serverTime())) end,
}
local CLASSES = { "guild", "friends", "global" }

local function FriendDest(name)
  return { key = "w:" .. Key(name), channel = "WHISPER", target = name }
end

-- Friends who answered the hello and are online now.
local confirmed = {} -- friend key -> name
local function ConfirmedOnline()
  local list = {}
  for key, name in pairs(confirmed) do
    if Roster.IsOnline(name) then list[#list + 1] = name end
  end
  table.sort(list)
  return list
end

local function Destinations(class)
  if class == "guild" then return { GUILD } end
  if class == "global" then return { GLOBAL } end
  local list = {}
  for _, name in ipairs(ConfirmedOnline()) do list[#list + 1] = FriendDest(name) end
  return list
end

local function CanSend(class)
  if not Consent.Allows(class, "send") then return false end
  if class == "global" then return Global.ChannelId() ~= nil end
  return class ~= "guild" or Roster.InGuild()
end

-- Queues what changed since the last announcement to every enabled class.
function Net.Sync()
  if not ns.db or type(ns.db.community) ~= "table" then return end
  for _, class in ipairs(CLASSES) do
    if CanSend(class) then
      local items = CurrentItems(class)
      local sent = SentSet(class)
      local current = {}
      for _, item in ipairs(items) do current[item.hash] = item end

      local retract, add = {}, {}
      for hash, mask in pairs(sent) do
        local item = current[hash]
        if not item then
          retract[#retract + 1] = hash
        elseif item.mask ~= mask then
          retract[#retract + 1] = hash
          add[#add + 1] = item
        end
      end
      for _, item in ipairs(items) do
        if sent[item.hash] == nil then add[#add + 1] = item end
      end
      table.sort(retract)

      for _, dest in ipairs(Destinations(class)) do
        for _, hash in ipairs(retract) do
          Queue(dest, { kind = "X", hash = hash, token = Hash.Token(Secret(), hash) })
        end
        for _, item in ipairs(add) do
          Queue(dest, { kind = "R", hash = item.hash, mask = item.mask, day = item.day,
            token = item.token, class = class })
        end
      end
      for _, hash in ipairs(retract) do sent[hash] = nil end
      for _, item in ipairs(add) do sent[item.hash] = item.mask end
    end
  end
  Kick()
end

-- The whole current list for one friend (a new addon user, or one back online).
local function Backlog(name)
  if not Consent.Allows("friends", "send") then return end
  local dest = FriendDest(name)
  for _, item in ipairs(CurrentItems("friends")) do
    Queue(dest, { kind = "R", hash = item.hash, mask = item.mask, day = item.day, token = item.token })
  end
  Kick()
end

-- Reports to a retraction of everything announced (consent revoked). Only the
-- classes that are still switched on can be told.
function Net.RetractAll()
  if not ns.db or type(ns.db.community) ~= "table" then return end
  for _, class in ipairs(CLASSES) do
    local sent = SentSet(class)
    if CanSend(class) then
      for _, dest in ipairs(Destinations(class)) do
        for hash in pairs(sent) do
          Queue(dest, { kind = "X", hash = hash, token = Hash.Token(Secret(), hash) })
        end
      end
    end
    ns.db.community.sent[class] = {}
  end
  Kick()
end

-- What the next report would contain, for the preview on the Community tab:
-- { hash =, mask =, labels = set, day =, token = } per qualifying own record.
function Net.Preview()
  local list = {}
  for _, item in ipairs(CurrentItems("friends")) do
    list[#list + 1] = { hash = item.hash, mask = item.mask, labels = Const.MaskToLabels(item.mask),
      day = item.day, token = item.token }
  end
  return list
end

-- --- Friends: hello and reply ------------------------------------------------------

local helloed = {}   -- friend key -> true once a hello went out this session
local repliedAt = {} -- friend key -> time of our last reply

local function Hello(name)
  local key = Key(name)
  if confirmed[key] or helloed[key] then return end
  helloed[key] = true
  Queue(FriendDest(name), { kind = "H1" })
end

local function FriendsOnline(names)
  if not Consent.Allows("friends", "send") then return end
  for _, name in ipairs(names) do
    if confirmed[Key(name)] then Backlog(name) else Hello(name) end
  end
  Kick()
end

-- Says hello to every friend who is online now (when sending to friends is switched on).
local function HelloAll()
  FriendsOnline(Roster.OnlineNames())
end

-- --- Receiving -----------------------------------------------------------------------

local rates = {} -- sender key -> { minuteAt, minuteCount, hourAt, hourCount }
local notifyPending = false

local function Notify()
  if notifyPending then return end
  notifyPending = true
  Net.io.after(CHANGE_DELAY, function()
    notifyPending = false
    Events:Fire(Const.Events.COMMUNITY_CHANGED)
  end)
end

-- How many of `wanted` records the sender may still add this minute and hour.
local function Allow(key, wanted)
  local now = Net.io.now()
  local state = rates[key]
  if not state then
    local size = 0
    for _ in pairs(rates) do size = size + 1 end
    if size > 2000 then rates = {} end
    state = { minuteAt = now, minuteCount = 0, hourAt = now, hourCount = 0 }
    rates[key] = state
  end
  if now - state.minuteAt >= 60 then state.minuteAt, state.minuteCount = now, 0 end
  if now - state.hourAt >= 3600 then state.hourAt, state.hourCount = now, 0 end
  local allowed = math.min(wanted, Limits.perMinute - state.minuteCount, Limits.perHour - state.hourCount)
  if allowed < 0 then allowed = 0 end
  state.minuteCount = state.minuteCount + allowed
  state.hourCount = state.hourCount + allowed
  return allowed
end

local function IsFriendOnWhisper(channel, name)
  return channel == "WHISPER" and Roster.IsFriend(name)
end

-- All senders of the global channel together may add this many records a minute;
-- the rest is dropped silently, so a flood cannot swamp the store.
local globalWindow = { at = 0, count = 0 }
local function GlobalAllow(wanted)
  local now = Net.io.now()
  if now - globalWindow.at >= 60 then globalWindow.at, globalWindow.count = now, 0 end
  local allowed = math.max(0, math.min(wanted, Limits.globalPerMinute - globalWindow.count))
  globalWindow.count = globalWindow.count + allowed
  return allowed
end

-- Passing on (section 8.10): a report seen for the first time is sent again after
-- 5 to 60 seconds, once, so that it reaches players who were not listening when
-- it was first sent. The reports seen are remembered, which is what stops loops.
-- Only a client that sends to the global channel passes reports on.
local relaySeen, relaySeenCount = {}, 0

local function Relay(item)
  local key = item.hash .. ":" .. item.token
  if relaySeen[key] then return end
  if relaySeenCount >= Limits.relaySeenCap then relaySeen, relaySeenCount = {}, 0 end
  relaySeen[key] = true
  relaySeenCount = relaySeenCount + 1
  if not (Consent.Allows("global", "send") and Global.ChannelId()) then return end
  if GlobalQueued() >= Limits.relayQueueCap then return end
  Net.io.after(Net.io.random(Limits.relayMin, Limits.relayMax), function()
    if not (Consent.Allows("global", "send") and Global.ChannelId()) then return end
    if GlobalQueued() >= Limits.relayQueueCap then return end
    Queue(GLOBAL, { kind = "R", hash = item.hash, mask = item.mask, day = item.day, token = item.token })
    Kick()
  end)
end

-- The report a global message carries: it is unscrambled with the current hour,
-- the one before and the one after, and the first that reads as a report wins.
local function OpenGlobal(text, today)
  for _, hour in ipairs(Envelope.Hours(Net.io.serverTime())) do
    local plain = Envelope.Decode(text, hour)
    local parsed = plain and Report.Parse(plain, today)
    if parsed and (parsed.kind == "R1" or parsed.kind == "X1") then return parsed end
  end
  return nil
end

local function ReceiveGlobal(name, text)
  local parsed = OpenGlobal(text, Hash.Day(Net.io.serverTime()))
  if not parsed then return end
  local allowed = math.min(Allow(Key(name), #parsed.items), GlobalAllow(#parsed.items))
  local changed = false
  for index = 1, allowed do
    local item = parsed.items[index]
    if parsed.kind == "R1" then
      if Aggregate.Add(item.hash, item.mask, item.day, item.token, "global") > 0 then changed = true end
      Relay(item)
    elseif Aggregate.Retract(item.hash, item.token, "global") then
      changed = true
    end
  end
  if changed then Notify() end
end

-- --- Self test ("/nbl check") ---------------------------------------------------------
-- Whispers a short message to the player's own character and waits for it to come
-- back. It proves, with nobody else involved, that the client accepts addon
-- whispers to a two-part name and delivers them to this addon.

local selfTest = nil -- { nonce =, done = }
local SELF_TEST_SECONDS = 3

-- Calls done(true) when the message came back, or done(false, "refused" | "noecho").
function Net.SelfTest(done)
  if selfTest then return end
  local parts = {}
  for index = 1, 4 do parts[index] = string.format("%02x", math.random(0, 255)) end
  local nonce = table.concat(parts)
  local me = Identity.Self()
  if me == "?" or not Net.io.send(PREFIX, "T1	" .. nonce, "WHISPER", me) then
    done(false, "refused")
    return
  end
  local test = { nonce = nonce, done = done }
  selfTest = test
  Net.io.after(SELF_TEST_SECONDS, function()
    if selfTest == test then
      selfTest = nil
      done(false, "noecho")
    end
  end)
end

-- Handles one addon message. Anything that fails a check is dropped silently.
function Net.OnMessage(prefix, message, channel, sender, channelName)
  if prefix ~= PREFIX then return end
  local text = Safe.Str(message)
  local name = Identity.Normalize(sender)
  if not text or not name then return end
  if Identity.Same(name, Identity.Self()) then
    -- Our own messages are ignored, except the echo of a running self test.
    local nonce = text:match("^T1	(%x%x%x%x%x%x%x%x)$")
    if nonce and channel == "WHISPER" and selfTest and selfTest.nonce == nonce then
      local test = selfTest
      selfTest = nil
      test.done(true)
    end
    return
  end
  if channel == "CHANNEL" then
    -- The global channel: only ours, only when receiving from it is switched on.
    if Global.IsOurs(channelName) and Consent.Allows("global", "receive") then ReceiveGlobal(name, text) end
    return
  end
  if channel ~= "GUILD" and channel ~= "WHISPER" then return end

  local parsed = Report.Parse(text, Hash.Day(Net.io.serverTime()))
  if not parsed then return end
  local key = Key(name)

  if parsed.kind == "H1" then
    -- A friend asks whether we run the addon: only answer when we accept reports.
    if not (IsFriendOnWhisper(channel, name) and Consent.Allows("friends", "receive")) then return end
    local now = Net.io.now()
    if repliedAt[key] and now - repliedAt[key] < HELLO_REPLY_SECONDS then return end
    repliedAt[key] = now
    Queue(FriendDest(name), { kind = "H2" })
    Kick()
    return
  end

  if parsed.kind == "H2" then
    -- A friend confirmed they run the addon: they get our reports from now on.
    if not (IsFriendOnWhisper(channel, name) and Consent.Allows("friends", "send")) then return end
    confirmed[key] = name
    Backlog(name)
    return
  end

  -- Reports and retractions: guild messages need the guild switch, whispers need
  -- the friends switch and a sender on the friend list.
  local source
  if channel == "GUILD" then
    if Consent.Allows("guild", "receive") then source = "guild" end
  elseif IsFriendOnWhisper(channel, name) and Consent.Allows("friends", "receive") then
    source = "friends"
  end
  if not source then return end

  local allowed = Allow(key, #parsed.items)
  local changed = false
  for index = 1, allowed do
    local item = parsed.items[index]
    if parsed.kind == "R1" then
      if Aggregate.Add(item.hash, item.mask, item.day, item.token, source, name) > 0 then changed = true end
    elseif Aggregate.Retract(item.hash, item.token, source) then
      changed = true
    end
  end
  if changed then Notify() end
end

-- --- Changes and set-up --------------------------------------------------------------

local enabledNow = {} -- class -> whether sending was on at the last check
local changePending = false

local function Changed()
  if changePending or not ns.db then return end
  changePending = true
  Net.io.after(CHANGE_DELAY, function()
    changePending = false
    for _, class in ipairs(CLASSES) do
      local on = CanSend(class)
      if on and not enabledNow[class] then
        -- Just switched on: send the whole backlog, not only what changed.
        SentSet(class) -- make sure the set exists
        ns.db.community.sent[class] = {}
        if class == "friends" then HelloAll() end
      end
      enabledNow[class] = on
    end
    Net.Sync()
  end)
end
Net.Changed = Changed

local function Maintain()
  Aggregate.Expire(Hash.Day(Net.io.serverTime()))
  Net.io.after(MAINTENANCE, Maintain)
end

local registered = false

-- Registers the prefix and starts listening. Returns false when the client has
-- no addon message API; the rest of Nullgate's Blacklist keeps working.
function Net.Register()
  if registered then return true end
  local register = C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix or RegisterAddonMessagePrefix
  if type(register) ~= "function" or type(CreateFrame) ~= "function" or type(C_Timer) ~= "table" then
    Output.Print(Output.Text("MSG_NO_COMMUNITY"))
    return false
  end
  pcall(register, PREFIX)
  local frame = CreateFrame("Frame")
  frame:RegisterEvent("CHAT_MSG_ADDON")
  frame:SetScript("OnEvent", function(_, _, prefix, message, channel, sender, _, _, _, channelName)
    Net.OnMessage(prefix, message, channel, sender, channelName)
  end)
  Roster.Register()
  Roster.OnOnline(FriendsOnline)
  for _, eventName in ipairs({ Const.Events.COMMUNITY_CHANGED, Const.Events.RECORDS_CHANGED,
    Const.Events.SETTINGS_CHANGED }) do
    Events:On(eventName, Changed)
  end
  for _, class in ipairs(CLASSES) do enabledNow[class] = CanSend(class) end
  registered = true
  Maintain()
  Changed()
  return true
end

-- Forgets the in-memory state (tests).
function Net.Reset()
  pending, destOrder, pumping = {}, {}, false
  confirmed, helloed, repliedAt, rates = {}, {}, {}, {}
  enabledNow, changePending, notifyPending = {}, false, false
  relaySeen, relaySeenCount, globalWindow = {}, 0, { at = 0, count = 0 }
  selfTest = nil
end
