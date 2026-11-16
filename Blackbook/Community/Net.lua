-- Blackbook: sending and receiving community reports in the background
-- (sections 8.6 and 8.7). Nothing here prints or asks: once the player has
-- opted in, reports about their Ignore entries go out quietly to the guild and
-- to friends who run the addon, and reports from those sources are filed.
--
-- Sending is one message at a time with a gap, one pending slot per target, and
-- is retried a few times. Receiving checks everything and drops silently.
-- The sender of a message is used for the checks and never stored.
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
}

local function Key(name) return string.lower(name) end

-- --- Outbox ----------------------------------------------------------------------
-- pending[destKey] = { channel =, target =, order = { itemKey... }, items = { itemKey = item } }
-- An item is { kind = "R" | "X" | "H1" | "H2", hash =, mask =, day =, token = }.
-- A newer report for the same target replaces an unsent one; a retraction cancels
-- an unsent report for that target.

local pending, destOrder = {}, {}
local pumping = false

local function ItemKey(item)
  if item.hash then return item.kind .. item.hash end
  return item.kind
end

local function Queue(dest, item)
  local slot = pending[dest.key]
  if not slot then
    slot = { channel = dest.channel, target = dest.target, order = {}, items = {} }
    pending[dest.key] = slot
    destOrder[#destOrder + 1] = dest.key
  end
  if item.kind == "X" then slot.items["R" .. item.hash] = nil end
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
  if Net.io.send(PREFIX, text, slot.channel, slot.target) then
    for _, key in ipairs(keys) do slot.items[key] = nil end
    -- Let the next destination go first.
    for index, existing in ipairs(destOrder) do
      if existing == destKey then
        table.remove(destOrder, index)
        destOrder[#destOrder + 1] = destKey
        break
      end
    end
    Net.io.after(Limits.sendGap, Pump)
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

-- --- What to send ------------------------------------------------------------------

local function Secret()
  return ns.db.community.install.secret
end

local function CurrentItems()
  return Report.Build(Records.All(), {
    shareLabels = Settings.Get("community.shareLabels") or {},
    secret = Secret(),
    now = Net.io.serverTime(),
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
  local list = {}
  for _, name in ipairs(ConfirmedOnline()) do list[#list + 1] = FriendDest(name) end
  return list
end

local function CanSend(class)
  if not Consent.Allows(class, "send") then return false end
  return class ~= "guild" or Roster.InGuild()
end

-- Queues what changed since the last announcement to every enabled class.
function Net.Sync()
  if not ns.db or type(ns.db.community) ~= "table" then return end
  local items
  for _, class in ipairs({ "guild", "friends" }) do
    if CanSend(class) then
      items = items or CurrentItems()
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
  for _, item in ipairs(CurrentItems()) do
    Queue(dest, { kind = "R", hash = item.hash, mask = item.mask, day = item.day, token = item.token })
  end
  Kick()
end

-- Reports to a retraction of everything announced (consent revoked). Only the
-- classes that are still switched on can be told.
function Net.RetractAll()
  if not ns.db or type(ns.db.community) ~= "table" then return end
  for _, class in ipairs({ "guild", "friends" }) do
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
  for _, item in ipairs(CurrentItems()) do
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

-- Handles one addon message. Anything that fails a check is dropped silently.
function Net.OnMessage(prefix, message, channel, sender)
  if prefix ~= PREFIX then return end
  local text = Safe.Str(message)
  local name = Identity.Normalize(sender)
  if not text or not name or Identity.Same(name, Identity.Self()) then return end
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
      if Aggregate.Add(item.hash, item.mask, item.day, item.token, source) > 0 then changed = true end
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
    for _, class in ipairs({ "guild", "friends" }) do
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
-- no addon message API; the rest of Blackbook keeps working.
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
  frame:SetScript("OnEvent", function(_, _, prefix, message, channel, sender)
    Net.OnMessage(prefix, message, channel, sender)
  end)
  Roster.Register()
  Roster.OnOnline(FriendsOnline)
  for _, eventName in ipairs({ Const.Events.COMMUNITY_CHANGED, Const.Events.RECORDS_CHANGED,
    Const.Events.SETTINGS_CHANGED }) do
    Events:On(eventName, Changed)
  end
  for _, class in ipairs({ "guild", "friends" }) do enabledNow[class] = CanSend(class) end
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
end
