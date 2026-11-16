-- Blackbook: community rules and the community verdict (sections 8.5, 8.8 and
-- 6.3). Community data on its own only ever produces a "notice"; a rule the
-- player creates can raise that to warn or ignore. Each source is evaluated on
-- its own, so friends, guild and global data are never mixed.
--
--   rule = { label = "scam", source = "guild", minTier = 2, verdict = "warn" }
local _, ns = ...

local Const = ns.Const
local Events = ns.Events
local Settings = ns.Settings
local Aggregate = ns.Aggregate
local Consent = ns.Consent
local Hash = ns.Hash

local Rules = {}
ns.Rules = Rules

local RANK = Const.VerdictRank
local MIN_GLOBAL = Const.Community.globalMinRuleTier

local VALID_SOURCE = {}
for _, source in ipairs(Const.Sources) do VALID_SOURCE[source] = true end

-- The locale key of the first problem with a rule, or nil when it is valid.
function Rules.Check(rule)
  if type(rule) ~= "table" then return "ERR_RULE" end
  if not Const.LabelValue[rule.label] then return "ERR_RULE" end
  if not VALID_SOURCE[rule.source] then return "ERR_RULE" end
  if rule.verdict ~= "warn" and rule.verdict ~= "ignore" then return "ERR_RULE" end
  local tier = rule.minTier
  if type(tier) ~= "number" or tier ~= math.floor(tier) or tier < 1 or tier > 4 then return "ERR_RULE" end
  if rule.source == "global" and tier < MIN_GLOBAL then return "ERR_RULE_GLOBAL" end
  return nil
end

function Rules.List()
  local list = Settings.Get("community.rules")
  return type(list) == "table" and list or {}
end

-- Adds a rule. Returns true, or false and a locale key. An identical rule
-- already present is not added twice.
function Rules.Add(rule)
  local err = Rules.Check(rule)
  if err then return false, err end
  local list = Rules.List()
  for _, existing in ipairs(list) do
    if existing.label == rule.label and existing.source == rule.source
      and existing.minTier == rule.minTier and existing.verdict == rule.verdict then
      return true
    end
  end
  local copy = { label = rule.label, source = rule.source, minTier = rule.minTier, verdict = rule.verdict }
  local updated = {}
  for index, existing in ipairs(list) do updated[index] = existing end
  updated[#updated + 1] = copy
  Settings.Set("community.rules", updated)
  Events:Fire(Const.Events.COMMUNITY_CHANGED)
  return true
end

function Rules.Remove(index)
  local list = Rules.List()
  if not list[index] then return false end
  local updated = {}
  for position, existing in ipairs(list) do
    if position ~= index then updated[#updated + 1] = existing end
  end
  Settings.Set("community.rules", updated)
  Events:Fire(Const.Events.COMMUNITY_CHANGED)
  return true
end

-- A rule never reacts below its own tier, and a global rule never below 3
-- (enforced here as well as in Check, in case the saved data was edited).
local function EffectiveTier(rule)
  local tier = tonumber(rule.minTier) or 4
  if rule.source == "global" and tier < MIN_GLOBAL then return MIN_GLOBAL end
  return tier
end

local function Hidden(hashes)
  local community = ns.db and ns.db.community
  local hidden = community and community.hidden
  if type(hidden) ~= "table" then return false end
  for _, hash in ipairs(hashes) do
    if hidden[hash] then return true end
  end
  return false
end

-- What one source says about one target hash: nil, or
-- { source =, verdict =, tier =, count =, labels = { id = { tier =, count = } } }.
local function ForSource(source, hash, today)
  local summary = Aggregate.Summary(hash, { source }, today)
  if not summary then return nil end
  local verdict = "notice"
  for _, rule in ipairs(Rules.List()) do
    if rule.source == source and Rules.Check(rule) == nil then
      local tier = Aggregate.Tier(hash, rule.label, { source }, today)
      if tier >= EffectiveTier(rule) and RANK[rule.verdict] > RANK[verdict] then
        verdict = rule.verdict
      end
    end
  end
  return { source = source, verdict = verdict, tier = summary.tier, count = summary.count, labels = summary.labels }
end

-- The community verdict for a target key. Returns the strongest verdict (or nil)
-- and one reason per receiving source that flags the player. Nothing comes back
-- when the player has not opted in, or has marked the flag as wrong.
function Rules.Evaluate(key)
  local receiving = Consent.Receiving()
  if #receiving == 0 then return nil, {} end
  local now = Hash.ServerTime()
  local today = Hash.Day(now)
  local hashes = Hash.Candidates(key, now)
  if Hidden(hashes) then return nil, {} end

  local best, reasons = nil, {}
  for _, source in ipairs(receiving) do
    local pick
    for _, hash in ipairs(hashes) do
      local found = ForSource(source, hash, today)
      if found and (not pick or RANK[found.verdict] > RANK[pick.verdict]
        or (RANK[found.verdict] == RANK[pick.verdict] and found.tier > pick.tier)) then
        pick = found
      end
    end
    if pick then
      reasons[#reasons + 1] = { source = "community", from = pick.source, verdict = pick.verdict,
        tier = pick.tier, count = pick.count, labels = pick.labels }
      if not best or RANK[pick.verdict] > RANK[best] then best = pick.verdict end
    end
  end
  return best, reasons
end

-- --- "This flag is wrong" (section 8.8) ----------------------------------------

-- Hides community data about a player on this install only; it is never shared.
-- The name is kept locally so the player can undo it later.
function Rules.Hide(name)
  local key = ns.Identity.Key(name)
  local community = ns.db and ns.db.community
  if not key or not community then return false end
  if type(community.hidden) ~= "table" then community.hidden = {} end
  for _, hash in ipairs(Hash.Candidates(key, Hash.ServerTime())) do
    community.hidden[hash] = ns.Identity.Normalize(name)
  end
  Events:Fire(Const.Events.COMMUNITY_CHANGED)
  return true
end

function Rules.Unhide(hash)
  local community = ns.db and ns.db.community
  if not community or type(community.hidden) ~= "table" or not community.hidden[hash] then return false end
  local name = community.hidden[hash]
  for other, value in pairs(community.hidden) do
    if value == name then community.hidden[other] = nil end
  end
  Events:Fire(Const.Events.COMMUNITY_CHANGED)
  return true
end

-- The hidden players as an array of { name =, hash = } (one entry per name).
function Rules.HiddenList()
  local community = ns.db and ns.db.community
  local list, seen = {}, {}
  if not community or type(community.hidden) ~= "table" then return list end
  for hash, name in pairs(community.hidden) do
    local label = type(name) == "string" and name or hash
    if not seen[label] then
      seen[label] = true
      list[#list + 1] = { name = label, hash = hash }
    end
  end
  table.sort(list, function(a, b) return string.lower(a.name) < string.lower(b.name) end)
  return list
end

-- True when the player hid community data about this name.
function Rules.IsHidden(name)
  local key = ns.Identity.Key(name)
  return key ~= nil and Hidden(Hash.Candidates(key, Hash.ServerTime()))
end
