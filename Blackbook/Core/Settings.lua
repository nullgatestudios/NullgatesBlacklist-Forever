-- Blackbook: saved variable, defaults, schema migrations and accessors
-- (section 5). Every change to the saved variable goes through the numbered
-- migration table below; no other file checks a version number.
local _, ns = ...

local Const = ns.Const
local Events = ns.Events

local Settings = {}
ns.Settings = Settings

local CURRENT_VERSION = 1

-- One entry per schema version. Migrations[n] converts saved data from
-- version n-1 to version n. Never edit a released entry; add a new one.
local Migrations = {
  [1] = function(db)
    db.records = db.records or {}
    db.subscriptions = db.subscriptions or {}
    db.community = db.community or {}
    db.community.install = db.community.install or {}
    db.community.reports = db.community.reports or {}
    db.community.hidden = db.community.hidden or {}
  end,
}

-- Default settings (section 5.3). Built fresh on every call so the returned
-- tables can be copied into the saved variable without sharing references.
local function Defaults()
  local shareLabels = {}
  local exportLabels = {}
  for _, entry in ipairs(Const.Labels) do
    exportLabels[entry.id] = true
    shareLabels[entry.id] = (entry.id ~= "private_dispute" and entry.id ~= "other")
  end
  return {
    language = "auto",
    hideChat = true,
    autoDecline = true,
    showNotices = true,
    showMinimap = true,
    minimapAngle = 220,
    replyMode = "none",
    setupDone = false,
    export = {
      id = nil,
      name = nil,
      labels = exportLabels,
      comments = true,
    },
    community = {
      friends = { send = false, receive = false },
      guild = { send = false, receive = false },
      global = { send = false, receive = false },
      shareLabels = shareLabels,
      consentVersion = 0,
      globalConsentVersion = 0,
      rules = {},
    },
  }
end

-- Fills missing keys from defaults, keeping every value the user already has.
local function ApplyDefaults(target, defaults)
  for key, value in pairs(defaults) do
    if type(value) == "table" then
      if type(target[key]) ~= "table" then target[key] = {} end
      ApplyDefaults(target[key], value)
    elseif target[key] == nil then
      target[key] = value
    end
  end
end

local seeded = false

local function RandomHex(byteCount)
  -- The WoW client seeds math.random itself and has no math.randomseed, so
  -- seeding is only done where the function exists (plain Lua, tests).
  if not seeded then
    seeded = true
    if type(math.randomseed) == "function" then
      local seed = 0
      if type(time) == "function" then seed = seed + time() end
      if type(GetTime) == "function" then seed = seed + math.floor(GetTime() * 100000) end
      math.randomseed(seed)
    end
  end
  local parts = {}
  for index = 1, byteCount do
    parts[index] = string.format("%02x", math.random(0, 255))
  end
  return table.concat(parts)
end

-- Loads the saved variable into ns.db, runs pending migrations and fills in
-- defaults. Returns the database and a state word: "newer" means the data was
-- written by a later build and is left untouched.
function Settings.Init()
  if type(BlackbookDB) ~= "table" then BlackbookDB = {} end
  local db = BlackbookDB
  local version = tonumber(db.version) or 0
  if version > CURRENT_VERSION then
    -- Written by a later build: keep ns.db unset so nothing can modify it.
    ns.db = nil
    return db, "newer"
  end
  for target = version + 1, CURRENT_VERSION do
    local migrate = Migrations[target]
    if migrate then migrate(db) end
    db.version = target
  end
  if type(db.settings) ~= "table" then db.settings = {} end
  ApplyDefaults(db.settings, Defaults())
  local exportId = db.settings.export.id
  if type(exportId) ~= "string" or #exportId ~= 12 or not exportId:match("^%x+$") then
    db.settings.export.id = RandomHex(6) -- 12 lowercase hex digits
  end
  if type(db.community) ~= "table" then db.community = {} end
  if type(db.community.install) ~= "table" then db.community.install = {} end
  local install = db.community.install
  if type(install.secret) ~= "string" or #install.secret ~= 32 or not install.secret:match("^%x+$") then
    install.secret = RandomHex(16) -- 32 lowercase hex digits; never leaves this install
  end
  ns.db = db
  return db
end

local function Split(path)
  local parts = {}
  for part in string.gmatch(path or "", "[^.]+") do
    parts[#parts + 1] = part
  end
  return parts
end

local function Walk(path)
  local db = ns.db
  if not db or type(db.settings) ~= "table" then return nil end
  local node = db.settings
  for _, part in ipairs(Split(path)) do
    if type(node) ~= "table" then return nil end
    node = node[part]
    if node == nil then return nil end
  end
  return node
end

-- Settings.Get("export.id"), Settings.Get("community.guild.send"), ...
function Settings.Get(path)
  if type(path) ~= "string" then return nil end
  if #Split(path) == 0 then return nil end
  return Walk(path)
end

-- Stores a setting and announces the change.
function Settings.Set(path, value)
  local db = ns.db
  if not db or type(db.settings) ~= "table" or type(path) ~= "string" then return nil end
  local parts = Split(path)
  if #parts == 0 then return nil end
  local node = db.settings
  for index = 1, #parts - 1 do
    local part = parts[index]
    if type(node[part]) ~= "table" then node[part] = {} end
    node = node[part]
  end
  node[parts[#parts]] = value
  Events:Fire(Const.Events.SETTINGS_CHANGED)
  return value
end

-- Stores the language choice ("auto" or a registered language code). Returns the
-- choice, or nil when it is not one of those.
function Settings.SetLanguage(choice)
  if not ns.Locale.IsValid(choice) then return nil end
  Settings.Set("language", choice)
  return choice
end
