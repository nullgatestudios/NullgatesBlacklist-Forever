-- Blackbook: the store of received community reports and the tier of a flag
-- (sections 8.3 and 8.4). Reports are filed per source, so friends, guild and
-- global data never mix:
--
--   db.community.reports[source][targetHash][labelId][token] = day
--
-- A flag's tier counts distinct tokens (distinct reporters) whose day lies in a
-- window. Nothing here stores who sent a report. Pure given ns.db.
local _, ns = ...

local Const = ns.Const

local Aggregate = {}
ns.Aggregate = Aggregate

local Limits = Const.Community

local VALID_SOURCE = {}
for _, source in ipairs(Const.Sources) do VALID_SOURCE[source] = true end

local function Community()
  local db = ns.db
  if db and type(db.community) == "table" then return db.community end
  return nil
end

local function Reports()
  local community = Community()
  if not community then return nil end
  if type(community.reports) ~= "table" then community.reports = {} end
  return community.reports
end

-- The counters live in the saved data so a rebuild is only needed once.
local function Counts(community)
  if type(community.tokenCount) ~= "number" or type(community.targetCount) ~= "table" then
    local tokens, targets = 0, {}
    for source, byHash in pairs(community.reports or {}) do
      targets[source] = 0
      for _, byLabel in pairs(byHash) do
        targets[source] = targets[source] + 1
        for _, byToken in pairs(byLabel) do
          for _ in pairs(byToken) do tokens = tokens + 1 end
        end
      end
    end
    community.tokenCount, community.targetCount = tokens, targets
  end
  return community
end

local function Adjust(community, source, tokenDelta, targetDelta)
  community.tokenCount = community.tokenCount + tokenDelta
  community.targetCount[source] = (community.targetCount[source] or 0) + targetDelta
end

local function ValidHash(text) return type(text) == "string" and #text == 16 and not text:find("[^0-9a-f]") end
local function ValidToken(text) return type(text) == "string" and #text == 8 and not text:find("[^0-9a-f]") end

-- Removes the oldest 5% of tokens when the whole store is full.
local function TrimOldest(community)
  local entries = {}
  for source, byHash in pairs(community.reports) do
    for hash, byLabel in pairs(byHash) do
      for label, byToken in pairs(byLabel) do
        for token, day in pairs(byToken) do
          entries[#entries + 1] = { day = day, source = source, hash = hash, label = label, token = token }
        end
      end
    end
  end
  table.sort(entries, function(a, b) return a.day < b.day end)
  for index = 1, math.max(1, math.floor(#entries / 20)) do
    local entry = entries[index]
    local byHash = community.reports[entry.source]
    local byLabel = byHash[entry.hash]
    local byToken = byLabel[entry.label]
    byToken[entry.token] = nil
    Adjust(community, entry.source, -1, 0)
    if next(byToken) == nil then byLabel[entry.label] = nil end
    if next(byLabel) == nil then
      byHash[entry.hash] = nil
      Adjust(community, entry.source, 0, -1)
    end
  end
end

-- Files one report: for every label bit in mask, the token is stored under the
-- source if it is not there yet (the first-seen day wins). Returns the number of
-- label entries that were new. Invalid input and a full target table add nothing.
function Aggregate.Add(hash, mask, day, token, source)
  local community = Community()
  if not community or not VALID_SOURCE[source] then return 0 end
  if not (ValidHash(hash) and ValidToken(token) and type(day) == "number") then return 0 end
  if type(mask) ~= "number" or mask < 1 or mask > Const.LabelMaskAll or mask ~= math.floor(mask) then return 0 end
  Counts(community)
  local reports = Reports()
  reports[source] = reports[source] or {}
  local byHash = reports[source]

  if not byHash[hash] and (community.targetCount[source] or 0) >= Limits.targetCap then return 0 end
  local added = 0
  for _, entry in ipairs(Const.Labels) do
    if mask % (entry.value * 2) >= entry.value then
      if community.tokenCount >= Limits.totalCap then TrimOldest(community) end
      if not byHash[hash] then
        byHash[hash] = {}
        Adjust(community, source, 0, 1)
      end
      local byToken = byHash[hash][entry.id]
      if not byToken then
        byToken = {}
        byHash[hash][entry.id] = byToken
      end
      if byToken[token] == nil then
        local count = 0
        local oldestToken, oldestDay
        for existing, existingDay in pairs(byToken) do
          count = count + 1
          if not oldestDay or existingDay < oldestDay then oldestToken, oldestDay = existing, existingDay end
        end
        if count >= Limits.tokenCap then
          byToken[oldestToken] = nil
          Adjust(community, source, -1, 0)
        end
        byToken[token] = day
        Adjust(community, source, 1, 0)
        added = added + 1
      end
    end
  end
  return added
end

-- Removes a token from a target in one source (a retraction from that source).
-- Returns true when something was removed.
function Aggregate.Retract(hash, token, source)
  local community = Community()
  local byHash = community and Reports() and Reports()[source]
  if not byHash or not byHash[hash] then return false end
  Counts(community)
  local removed = false
  for label, byToken in pairs(byHash[hash]) do
    if byToken[token] ~= nil then
      byToken[token] = nil
      Adjust(community, source, -1, 0)
      removed = true
      if next(byToken) == nil then byHash[hash][label] = nil end
    end
  end
  if next(byHash[hash]) == nil then
    byHash[hash] = nil
    Adjust(community, source, 0, -1)
  end
  return removed
end

-- The distinct tokens of one label across some sources, as { token = earliest day }.
-- Only sources of one group (friends and guild, or global) are combined.
local function Tokens(hash, label, sources)
  local set = {}
  local reports = Reports() or {}
  for _, source in ipairs(sources) do
    local byToken = reports[source] and reports[source][hash] and reports[source][hash][label]
    if byToken then
      for token, day in pairs(byToken) do
        if not set[token] or day < set[token] then set[token] = day end
      end
    end
  end
  return set
end

local function CountInWindow(set, today, days)
  local count = 0
  for _, day in pairs(set) do
    if today - day < days and day <= today + Limits.futureDays then count = count + 1 end
  end
  return count
end

local function GroupOf(sources)
  return Const.SourceGroup[sources[1]]
end

-- The tier (0 to 4) of a label on a target, and the distinct reporters in the
-- longest window. `sources` must all belong to one group; mixing friends/guild
-- with global is refused (returns 0), because those worlds are kept apart.
function Aggregate.Tier(hash, label, sources, today)
  if type(sources) ~= "table" or #sources == 0 then return 0, 0 end
  local group = GroupOf(sources)
  for _, source in ipairs(sources) do
    if Const.SourceGroup[source] ~= group then return 0, 0 end
  end
  local set = Tokens(hash, label, sources)
  local tier = 0
  for _, step in ipairs(Const.Tiers[group]) do
    if CountInWindow(set, today, step.days) >= step.reports then tier = math.max(tier, step.tier) end
  end
  return tier, CountInWindow(set, today, Limits.windowDays)
end

-- Overview of a target for one group of sources: the highest tier over all
-- labels, the distinct reporters over all labels and each label's tier.
-- Returns nil when nothing reached tier 1.
function Aggregate.Summary(hash, sources, today)
  if type(sources) ~= "table" or #sources == 0 then return nil end
  local best, labels, everyone = 0, {}, {}
  for _, entry in ipairs(Const.Labels) do
    local tier, count = Aggregate.Tier(hash, entry.id, sources, today)
    if tier > 0 then
      labels[entry.id] = { tier = tier, count = count }
      best = math.max(best, tier)
    end
    for token, day in pairs(Tokens(hash, entry.id, sources)) do
      if today - day < Limits.windowDays then everyone[token] = true end
    end
  end
  if best == 0 then return nil end
  local reporters = 0
  for _ in pairs(everyone) do reporters = reporters + 1 end
  return { tier = best, count = reporters, labels = labels }
end

-- Drops reports older than the window and the tables they leave empty.
function Aggregate.Expire(today)
  local community = Community()
  local reports = Reports()
  if not community or not reports then return end
  Counts(community)
  for source, byHash in pairs(reports) do
    for hash, byLabel in pairs(byHash) do
      for label, byToken in pairs(byLabel) do
        for token, day in pairs(byToken) do
          if today - day > Limits.windowDays then
            byToken[token] = nil
            Adjust(community, source, -1, 0)
          end
        end
        if next(byToken) == nil then byLabel[label] = nil end
      end
      if next(byLabel) == nil then
        byHash[hash] = nil
        Adjust(community, source, 0, -1)
      end
    end
  end
end

-- Empties the store (consent revoked).
function Aggregate.Purge()
  local community = Community()
  if not community then return end
  community.reports = {}
  community.tokenCount, community.targetCount = 0, {}
end

-- Tokens and targets held, for tests and the Community tab.
function Aggregate.Counts()
  local community = Community()
  if not community then return 0, 0 end
  Counts(community)
  local targets = 0
  for _, count in pairs(community.targetCount) do targets = targets + count end
  return community.tokenCount, targets
end
