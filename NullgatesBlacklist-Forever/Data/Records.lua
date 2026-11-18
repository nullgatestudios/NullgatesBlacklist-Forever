-- Nullgate's Blacklist: the player's own list (section 6.2). A record needs at least one
-- label and a non-empty trimmed comment. Every mutation fires
-- RECORDS_CHANGED; nothing here touches the UI.
local _, ns = ...

local Const = ns.Const
local Events = ns.Events
local Safe = ns.Safe
local Identity = ns.Identity

local Records = {}
ns.Records = Records

local function Store()
  local db = ns.db
  if db and type(db.records) == "table" then return db.records end
  return nil
end

local function Trim(text)
  if type(strtrim) == "function" then return strtrim(text) end
  return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Returns the record for a name, or nil.
function Records.Get(name)
  local store = Store()
  local key = Identity.Key(name)
  if not store or not key then return nil end
  return store[key]
end

-- Copies a label set and drops unknown ids. Returns the copy and its size.
local function CopyLabels(labels)
  local copy, count = {}, 0
  if type(labels) ~= "table" then return copy, 0 end
  for id, on in pairs(labels) do
    if on and Const.LabelValue[id] then
      copy[id] = true
      count = count + 1
    end
  end
  return copy, count
end

-- Validates and normalizes the fields of a record. Returns a table with the
-- clean name, labels and comment, or nil and a locale key naming the problem.
local function Prepare(name, verdict, labels, comment)
  local normalized = Identity.Normalize(name)
  if not normalized then return nil, "ERR_NAME" end
  if verdict ~= "ignore" and verdict ~= "warn" then return nil, "ERR_VERDICT" end
  local copy, labelCount = CopyLabels(labels)
  if labelCount == 0 then return nil, "ERR_LABELS" end
  local text = Safe.Str(comment)
  text = text and Trim(text) or ""
  if text == "" then return nil, "ERR_COMMENT" end
  if Identity.CharCount(text) > Const.Limits.comment then return nil, "ERR_COMMENT_LENGTH" end
  return { name = normalized, labels = copy, comment = text }
end

-- The locale key of the first problem with these fields, or nil when they are
-- valid. The editor uses this to enable its Save button.
function Records.Check(name, verdict, labels, comment)
  local _, err = Prepare(name, verdict, labels, comment)
  return err
end

-- Creates or updates a record. Returns the record, or nil and a locale key
-- describing what is missing.
function Records.Save(name, verdict, labels, comment)
  local store = Store()
  if not store then return nil, "ERR_DB" end
  local clean, err = Prepare(name, verdict, labels, comment)
  if not clean then return nil, err end
  local normalized, copy, text = clean.name, clean.labels, clean.comment

  local key = string.lower(normalized)
  local now = time()
  local record = store[key]
  if record then
    record.name = normalized
    record.verdict = verdict
    record.labels = copy
    record.comment = text
    record.updated = now
  else
    record = {
      name = normalized,
      verdict = verdict,
      labels = copy,
      comment = text,
      created = now,
      updated = now,
      addedBy = Identity.Self(),
    }
    store[key] = record
  end
  Events:Fire(Const.Events.RECORDS_CHANGED)
  return record
end

-- Deletes the record for a name. True when something was removed.
function Records.Remove(name)
  local store = Store()
  local key = Identity.Key(name)
  if not store or not key or not store[key] then return false end
  store[key] = nil
  Events:Fire(Const.Events.RECORDS_CHANGED)
  return true
end

-- All records as an array, sorted by name.
function Records.All()
  local store = Store()
  local list = {}
  if not store then return list end
  for _, record in pairs(store) do
    list[#list + 1] = record
  end
  table.sort(list, function(a, b)
    local nameA, nameB = string.lower(a.name), string.lower(b.name)
    if nameA == nameB then return a.name < b.name end
    return nameA < nameB
  end)
  return list
end
