-- Nullgate's Blacklist: all fixed names, prefixes, limits and tables in one place
-- (section 4.1). Pure module: nothing here touches a WoW global at load time.
local _, ns = ...

local Const = {}
ns.Const = Const

Const.ADDON_NAME = "NullgatesBlacklist-Forever"  -- the addon folder
Const.DISPLAY_NAME = "Nullgate's Blacklist"
Const.SAVED_VARIABLE = "NullgatesBlacklistDB"

-- The addon icon (assets/icon.svg rendered to a 128x128 TGA): used by the TOC
-- IconTexture line and by the minimap button.
Const.ICON = "Interface/AddOns/" .. Const.ADDON_NAME .. "/icon.tga"

-- Section 6.5.
Const.SLASH_LONG = "/blacklist"
Const.SLASH_SHORT = "/nbl"

-- Wire prefixes (sections 7.1, 8.6). They stay distinct because the
-- game throttles bursts per prefix.
Const.CODE_PREFIX = "BK1"
Const.COMMUNITY_PREFIX = "BKC"

-- Limits used by validation (sections 6.2, 7.3, 7.4).
Const.Limits = {
  name = 60,
  comment = 255,
  listName = 60,
  author = 60,
  recordsPerList = 5000,
  codeBytes = 5400000,    -- longest pasted code accepted (5000 records, Base64)
  payloadBytes = 4000000, -- longest payload after decoding or decompressing
  subscriptions = 50,     -- imported lists kept at once
}

-- Labels (section 5.1). Fixed order; never renumber, never rename an ID.
Const.Labels = {
  { id = "harassment", bit = 1 },
  { id = "hate", bit = 2 },
  { id = "toxicity", bit = 3 },
  { id = "griefing", bit = 4 },
  { id = "ninja_loot", bit = 5 },
  { id = "scam", bit = 6 },
  { id = "spam", bit = 7 },
  { id = "private_dispute", bit = 8 },
  { id = "other", bit = 9 },
}

-- Integer values of the label bits, built without the bit library so the
-- module stays testable with plain Lua 5.1.
local bitValue = {}
do
  local value = 1
  for bit = 1, #Const.Labels do
    bitValue[bit] = value
    value = value * 2
  end
end

Const.LabelValue = {}
Const.LabelById = {}
for _, entry in ipairs(Const.Labels) do
  entry.value = bitValue[entry.bit]
  Const.LabelValue[entry.id] = entry.value
  Const.LabelById[entry.bit] = entry
end

Const.LabelMaskAll = 511

-- Locale key of a label, for example "harassment" -> "LABEL_HARASSMENT".
function Const.LabelLocaleKey(id)
  return "LABEL_" .. string.upper(id)
end

-- Label set { [id] = true } -> integer bitmask.
function Const.LabelsToMask(set)
  local mask = 0
  if type(set) ~= "table" then return 0 end
  for id, on in pairs(set) do
    local value = Const.LabelValue[id]
    if on and value then mask = mask + value end
  end
  return mask
end

-- Integer bitmask -> label set. Unknown bits are dropped (section 7.3).
function Const.MaskToLabels(mask)
  local set = {}
  if type(mask) ~= "number" then return set end
  for _, entry in ipairs(Const.Labels) do
    local value = entry.value
    if mask % (value * 2) >= value then set[entry.id] = true end
  end
  return set
end

-- Verdict strength (section 3): ignore > warn > notice.
Const.VerdictRank = { ignore = 3, warn = 2, notice = 1 }

-- A hidden whisper is announced at most once per person in this many seconds
-- (section 6.4).
Const.WhisperNoticeSeconds = 60

-- Tier thresholds (section 8.3). A tier needs that many distinct reports
-- within its window. Kept in one table so the numbers are easy to review.
Const.Tiers = {
  friends = {
    { tier = 1, reports = 3, days = 90 },
    { tier = 2, reports = 7, days = 30 },
    { tier = 3, reports = 10, days = 7 },
    { tier = 4, reports = 15, days = 1 },
  },
  global = {
    { tier = 1, reports = 5, days = 90 },
    { tier = 2, reports = 12, days = 30 },
    { tier = 3, reports = 20, days = 7 },
    { tier = 4, reports = 30, days = 1 },
  },
}

-- Community sources (section 8). Friends and guild share one set of tier
-- thresholds but are stored and evaluated separately; "global" (M9) is a
-- separate world with its own thresholds and is never mixed with them.
Const.Sources = { "friends", "guild", "global" }
Const.SourceGroup = { friends = "friends", guild = "friends", global = "global" }

-- Community limits (sections 8.4, 8.6, 8.7).
Const.Community = {
  recordsPerMessage = 6,
  windowDays = 90,        -- reports older than this expire
  futureDays = 1,         -- a report day this far ahead is still accepted
  targetCap = 20000,      -- distinct targets per source
  tokenCap = 50,          -- tokens per target and label
  totalCap = 200000,      -- tokens in the whole store
  perMinute = 30,         -- records accepted per sender and minute
  perHour = 600,          -- ... and per hour
  sendGap = 0.5,          -- seconds between two outgoing messages
  retries = 3,            -- send attempts per message
  retryDelay = 5,         -- seconds before a failed send is tried again
  globalMinRuleTier = 3,  -- a global rule cannot be set to react below this tier
  globalGap = 2,          -- seconds between two messages on the global channel
  globalPerMinute = 600,  -- records accepted per minute from all global senders together
  relayMin = 5,           -- a received global report is passed on after this many seconds ...
  relayMax = 60,          -- ... to this many
  relaySeenCap = 20000,   -- reports remembered so each is passed on once
  relayQueueCap = 500,    -- passing on stops while this many global messages wait
}

-- The global channel (section 8.10): one fixed channel name, and a version for its
-- own, separate consent text.
Const.GLOBAL_CHANNEL = "BlackbookGl"
Const.GlobalConsentVersion = 1

-- Constant part of the key of the message envelope on the global channel.
Const.EnvelopeSalt = "blackbook-envelope-v1"

-- Hash inputs (section 8.2).
Const.SeasonSalt = "blackbook-season-v1"
Const.SeasonDays = 90

-- Version of the community disclosure text (section 8.9).
Const.ConsentVersion = 1

-- Names used on the internal bus (section 4.3).
Const.Events = {
  RECORDS_CHANGED = "RECORDS_CHANGED",
  SUBSCRIPTIONS_CHANGED = "SUBSCRIPTIONS_CHANGED",
  COMMUNITY_CHANGED = "COMMUNITY_CHANGED",
  SETTINGS_CHANGED = "SETTINGS_CHANGED",
}
