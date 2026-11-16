-- Blackbook: the effective verdict for a player (section 6.3). Own records
-- win; otherwise the strongest verdict among imported lists applies. Community
-- sources join in M8. Results are cached per target key and the cache is
-- cleared on every bus event that can change the answer.
local _, ns = ...

local Const = ns.Const
local Events = ns.Events
local Identity = ns.Identity

local Resolver = {}
ns.Resolver = Resolver

local RANK = Const.VerdictRank

local cache = {}

local function ClearCache()
  cache = {}
end

for _, eventName in pairs(Const.Events) do
  Events:On(eventName, ClearCache)
end

local function Stronger(a, b)
  if not a then return b end
  if not b then return a end
  if RANK[b] > RANK[a] then return b end
  return a
end

-- The verdict one imported entry produces: the strongest rule among its labels,
-- "notice" when no label has a rule.
local function EntryVerdict(entry, rules)
  local best
  if type(entry.labels) == "table" and type(rules) == "table" then
    for id, on in pairs(entry.labels) do
      local rule = rules[id]
      if on and RANK[rule] then best = Stronger(best, rule) end
    end
  end
  return best or "notice"
end

local function Compute(key)
  local db = ns.db
  if not db then return nil, {} end

  local own = type(db.records) == "table" and db.records[key] or nil
  if own then
    return own.verdict, {
      { source = "own", verdict = own.verdict, labels = own.labels, comment = own.comment },
    }
  end

  local best, reasons = nil, {}
  if type(db.subscriptions) == "table" then
    for _, list in pairs(db.subscriptions) do
      local entry = type(list.records) == "table" and list.records[key] or nil
      if entry then
        local verdict = EntryVerdict(entry, list.rules)
        reasons[#reasons + 1] = {
          source = "list", verdict = verdict, labels = entry.labels,
          comment = entry.comment, list = list.name, author = list.author, listId = list.id,
        }
        best = Stronger(best, verdict)
      end
    end
  end
  table.sort(reasons, function(a, b)
    if a.verdict ~= b.verdict then return RANK[a.verdict] > RANK[b.verdict] end
    return tostring(a.listId) < tostring(b.listId)
  end)
  return best, reasons
end

local function Lookup(name)
  local key = Identity.Key(name)
  if not key then return nil, {} end
  local hit = cache[key]
  if not hit then
    local verdict, reasons = Compute(key)
    hit = { verdict = verdict, reasons = reasons }
    cache[key] = hit
  end
  return hit.verdict, hit.reasons
end

-- Returns "ignore", "warn", "notice" or nil, plus the reason list. The reason
-- list is shared with the cache: callers must not modify it.
function Resolver.Verdict(name)
  return Lookup(name)
end

-- The detailed reasons only, for tooltips and the manager.
function Resolver.Sources(name)
  local _, reasons = Lookup(name)
  return reasons
end
