-- Blackbook: imported lists and the player's label rules for them (sections
-- 5.2 and 7.3). A subscription is stored under its list id; importing the same
-- id again replaces the records and keeps the rules. Every change fires
-- SUBSCRIPTIONS_CHANGED.
local _, ns = ...

local Const = ns.Const
local Events = ns.Events
local Identity = ns.Identity
local Output = ns.Output
local Records = ns.Records

local Subscriptions = {}
ns.Subscriptions = Subscriptions

local RULE_VERDICTS = { notice = true, warn = true, ignore = true }

local function Store()
  local db = ns.db
  if db and type(db.subscriptions) == "table" then return db.subscriptions end
  return nil
end

function Subscriptions.Get(id)
  local store = Store()
  return store and store[id] or nil
end

local function Count(store)
  local count = 0
  for _ in pairs(store) do count = count + 1 end
  return count
end

-- Stores a decoded list (Codec.Decode). Returns the subscription and whether it
-- replaced an earlier copy, or nil and a locale key. The player's own character
-- is dropped from the records: a list must never hide the player's own chat.
function Subscriptions.Import(list)
  local store = Store()
  if not store then return nil, "ERR_DB" end
  if list.id == ns.Settings.Get("export.id") then return nil, "ERR_OWN_LIST" end
  local existing = store[list.id]
  if not existing and Count(store) >= Const.Limits.subscriptions then
    return nil, "ERR_TOO_MANY_LISTS"
  end

  local records, count = {}, 0
  local self = Identity.Self()
  for key, entry in pairs(list.records) do
    if not Identity.Same(entry.name, self) then
      records[key] = entry
      count = count + 1
    end
  end
  local subscription = {
    id = list.id, name = list.name, author = list.author, exported = list.exported,
    imported = time(), records = records, count = count,
    rules = existing and existing.rules or {},
  }
  store[list.id] = subscription
  Events:Fire(Const.Events.SUBSCRIPTIONS_CHANGED)
  return subscription, existing ~= nil
end

-- One line saying what an import did, for chat and the Share tab.
function Subscriptions.Summary(subscription, replaced)
  return string.format(Output.Text(replaced and "IMPORT_UPDATED" or "IMPORT_DONE"),
    Output.Escape(subscription.name), Output.Escape(subscription.author), subscription.count)
end

function Subscriptions.Remove(id)
  local store = Store()
  if not store or not store[id] then return false end
  store[id] = nil
  Events:Fire(Const.Events.SUBSCRIPTIONS_CHANGED)
  return true
end

-- All subscriptions, sorted by name (then id).
function Subscriptions.All()
  local list = {}
  for _, subscription in pairs(Store() or {}) do list[#list + 1] = subscription end
  table.sort(list, function(a, b)
    local nameA, nameB = string.lower(a.name), string.lower(b.name)
    if nameA ~= nameB then return nameA < nameB end
    return a.id < b.id
  end)
  return list
end

-- The verdict a label produces for a list: "notice" unless a rule says more.
function Subscriptions.Rule(id, label)
  local subscription = Subscriptions.Get(id)
  local rule = subscription and subscription.rules and subscription.rules[label]
  return RULE_VERDICTS[rule] and rule or "notice"
end

-- Sets what a label means for one list. "notice" is the default, so it is
-- stored by removing the rule. Returns false for an unknown list, label or verdict.
function Subscriptions.SetRule(id, label, verdict)
  local subscription = Subscriptions.Get(id)
  if not subscription or not Const.LabelValue[label] or not RULE_VERDICTS[verdict] then
    return false
  end
  if type(subscription.rules) ~= "table" then subscription.rules = {} end
  subscription.rules[label] = verdict ~= "notice" and verdict or nil
  Events:Fire(Const.Events.SUBSCRIPTIONS_CHANGED)
  return true
end

-- Every imported entry as one array for the Imported tab. "verdict" is the
-- effective verdict, so an entry the player overrides shows the own record's.
function Subscriptions.Entries()
  local entries = {}
  for _, subscription in pairs(Store() or {}) do
    for _, entry in pairs(subscription.records) do
      local own = Records.Get(entry.name)
      entries[#entries + 1] = {
        name = entry.name, labels = entry.labels, comment = entry.comment,
        created = entry.created, list = subscription.name, listId = subscription.id,
        verdict = ns.Resolver.Verdict(entry.name) or "notice", own = own ~= nil,
      }
    end
  end
  return entries
end
