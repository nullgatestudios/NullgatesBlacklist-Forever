-- Blackbook: all fixed names, prefixes, limits and tables in one place
-- (section 4.1). Pure module: nothing here touches a WoW global at load time.
local _, ns = ...

local Const = {}
ns.Const = Const

Const.ADDON_NAME = "Blackbook"
Const.SAVED_VARIABLE = "BlackbookDB"

-- Section 6.5.
Const.SLASH_BLACKBOOK = "/blackbook"
Const.SLASH_BLACKBOOK_SHORT = "/bb"

-- Wire prefixes (sections 7.1, 7.4, 8.6). They stay distinct because the
-- game throttles bursts per prefix.
Const.CODE_PREFIX = "BK1"
Const.TRANSFER_PREFIX = "BKX"
Const.COMMUNITY_PREFIX = "BKC"

-- Limits used by validation (sections 6.2, 7.3, 7.4).
Const.Limits = {
  name = 60,
  comment = 255,
  listName = 60,
  author = 60,
  recordsPerList = 5000,
  transferChunk = 200,
  transferParts = 600,
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
