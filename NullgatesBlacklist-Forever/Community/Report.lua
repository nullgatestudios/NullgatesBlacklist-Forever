-- Nullgate's Blacklist: what gets reported and the wire format of community messages
-- (sections 8.6 and 8.7). Pure module.
--
--   R1 <TAB> hash:mask:day:token;hash:mask:day:token;...   reports (at most 6)
--   X1 <TAB> hash:token;hash:token;...                      retractions (at most 6)
--   H1 / H2                                                 hello and its reply
--
-- Only own records with verdict "ignore" are reported, only with labels the
-- player chose to share, and never with a comment or a name.
local _, ns = ...

local Const = ns.Const
local Hash = ns.Hash
local Identity = ns.Identity

local Report = {}
ns.Report = Report

local Limits = Const.Community
local MAX_BYTES = 255

-- Items for every own record that qualifies:
-- { key =, hash =, mask =, day =, token = }, sorted by hash.
-- records: array of own records; opts = { shareLabels = set, secret = text, now = server time,
-- group = "friends" | "global" (the source group the reports are for; it picks the hash salt) }.
function Report.Build(records, opts)
  local items = {}
  local season, today = Hash.Season(opts.now), Hash.Day(opts.now)
  for _, record in ipairs(records) do
    if record.verdict == "ignore" then
      local shared = {}
      for id, on in pairs(record.labels or {}) do
        if on and opts.shareLabels[id] then shared[id] = true end
      end
      local mask = Const.LabelsToMask(shared)
      local key = Identity.Key(record.name)
      if mask > 0 and key then
        local hash = Hash.Target(key, season, opts.group)
        local created = Hash.Day(record.created or opts.now)
        items[#items + 1] = {
          key = key, hash = hash, mask = mask,
          day = math.max(math.min(created, today), today - (Limits.windowDays - 1)),
          token = Hash.Token(opts.secret, hash),
        }
      end
    end
  end
  table.sort(items, function(a, b) return a.hash < b.hash end)
  return items
end

local function Batches(parts, head)
  local messages = {}
  for first = 1, #parts, Limits.recordsPerMessage do
    local slice = {}
    for index = first, math.min(first + Limits.recordsPerMessage - 1, #parts) do
      slice[#slice + 1] = parts[index]
    end
    messages[#messages + 1] = head .. "\t" .. table.concat(slice, ";")
  end
  return messages
end

-- Report messages for items (see Build), six to a message.
function Report.Messages(items)
  local parts = {}
  for _, item in ipairs(items) do
    parts[#parts + 1] = string.format("%s:%d:%d:%s", item.hash, item.mask, item.day, item.token)
  end
  return Batches(parts, "R1")
end

-- Retraction messages for { hash =, token = } pairs.
function Report.RetractMessages(pairs_)
  local parts = {}
  for _, item in ipairs(pairs_) do parts[#parts + 1] = item.hash .. ":" .. item.token end
  return Batches(parts, "X1")
end

local function IsHex(text, length)
  return #text == length and not text:find("[^0-9a-f]")
end

-- Reads a received message. Returns a table { kind = "R1" | "X1" | "H1" | "H2",
-- items = { ... } } or nil for anything malformed. Records that fail their
-- checks are dropped one by one, the rest of the message is kept.
-- today is Hash.Day of the current server time.
function Report.Parse(text, today)
  if type(text) ~= "string" or #text > MAX_BYTES then return nil end
  local word, rest = text:match("^(%u%d)(.*)$")
  if word == "H1" or word == "H2" then
    if rest ~= "" then return nil end
    return { kind = word, items = {} }
  end
  if word ~= "R1" and word ~= "X1" then return nil end
  local body = rest:match("^\t(.+)$")
  if not body then return nil end

  local items = {}
  local seen = 0
  for part in body:gmatch("[^;]+") do
    seen = seen + 1
    if seen > Limits.recordsPerMessage then break end
    if word == "R1" then
      local hash, mask, day, token = part:match("^(%x+):(%d+):(%d+):(%x+)$")
      if hash and IsHex(hash, 16) and IsHex(token, 8) and #mask <= 3 and #day <= 7 then
        mask = tonumber(mask) % (Const.LabelMaskAll + 1) -- keep the known label bits only
        day = tonumber(day)
        if mask >= 1 and day <= today + Limits.futureDays and today - day <= Limits.windowDays then
          items[#items + 1] = { hash = hash, mask = mask, day = day, token = token }
        end
      end
    else
      local hash, token = part:match("^(%x+):(%x+)$")
      if hash and IsHex(hash, 16) and IsHex(token, 8) then
        items[#items + 1] = { hash = hash, token = token }
      end
    end
  end
  return { kind = word, items = items }
end
