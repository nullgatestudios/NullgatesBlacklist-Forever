-- Blackbook: pure-module tests (DESIGN.md section 11).
--
-- Run from the repository root:
--     lua5.1 tests/run.lua      (lua tests/run.lua works too)
--
-- No WoW client is involved. Only the few globals the pure modules read are
-- stubbed below. The harness and the modules stay Lua 5.1 compatible.

-- --- WoW stubs ---------------------------------------------------------------
function strtrim(text)
  return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

function time()
  return 1700000000
end

local SECRET = "a-secret-value"

-- --- Load the modules the way the client does -------------------------------
-- Each module is a file chunk called with (addonName, sharedTable), which is
-- what the client passes to addon files.

local source = debug.getinfo(1, "S").source or ""
local script = source:match("^@(.*)$") or "tests/run.lua"
local scriptDir = script:match("^(.*)[/\\][^/\\]*$") or "."
local root = scriptDir:match("^(.*)[/\\][^/\\]*$") or "."

local ns = {}
local function Load(relative)
  local path = root .. "/Blackbook/" .. relative
  local chunk = assert(loadfile(path), "cannot load " .. path)
  chunk("Blackbook", ns)
end

Load("Locale/enUS.lua")
Load("Core/Const.lua")
Load("Core/Events.lua")
Load("Core/Safe.lua")
Load("Core/Output.lua")
Load("Core/Identity.lua")
Load("Core/Settings.lua")
Load("Data/Records.lua")
Load("Data/Subscriptions.lua")
Load("Data/Resolver.lua")
Load("Display/Markers.lua")
Load("Enforce/Chat.lua")
Load("Enforce/Requests.lua")
Load("Display/Portrait.lua")
Load("Display/Tooltip.lua")
Load("UI/Widgets.lua")
Load("UI/Editor.lua")
Load("UI/ContextMenu.lua")
Load("Data/Query.lua")
Load("Share/Wire.lua")
Load("Share/Codec.lua")
Load("Share/Transfer.lua")
Load("UI/Manager.lua")
Load("UI/TabList.lua")
Load("UI/TabSettings.lua")
Load("UI/Minimap.lua")

-- --- Assertions --------------------------------------------------------------

local checks, failures = 0, 0

local function Display(value)
  if type(value) == "string" then return string.format("%q", value) end
  return tostring(value)
end

local function Report(ok, label, detail)
  checks = checks + 1
  if ok then return end
  failures = failures + 1
  if detail then
    print("FAIL " .. label .. ": " .. detail)
  else
    print("FAIL " .. label)
  end
end

local function EQ(actual, expected, label)
  local ok = actual == expected
  Report(ok, label, ok and nil or ("expected " .. Display(expected) .. ", got " .. Display(actual)))
end

local function OK(condition, label)
  Report(condition and true or false, label)
end

local function Group(name, fn)
  local ok, err = pcall(fn)
  if not ok then
    failures = failures + 1
    print("ERROR " .. name .. ": " .. tostring(err))
  end
end

-- --- Const: labels and masks (section 5.1) -----------------------------------

Group("Const labels", function()
  local Const = ns.Const
  EQ(Const.LabelsToMask({ harassment = true }), 1, "harassment bit")
  EQ(Const.LabelsToMask({ harassment = true, scam = true }), 33, "two labels add up")
  EQ(Const.LabelsToMask({}), 0, "empty set")
  EQ(Const.LabelsToMask({ unknown = true }), 0, "unknown id ignored")
  EQ(Const.LabelsToMask(nil), 0, "nil set")
  EQ(Const.LabelsToMask(Const.MaskToLabels(Const.LabelMaskAll)), Const.LabelMaskAll, "round trip of all labels")
  EQ(Const.LabelsToMask(Const.MaskToLabels(Const.LabelMaskAll + 1024)), Const.LabelMaskAll, "unknown bits dropped")
  local set = Const.MaskToLabels(Const.LabelsToMask({ hate = true, other = true }))
  OK(set.hate and set.other and not set.scam, "set survives a round trip")
  EQ(next(Const.MaskToLabels(0)), nil, "mask 0 is empty")
  EQ(Const.LabelLocaleKey("ninja_loot"), "LABEL_NINJA_LOOT", "locale key")
end)

-- --- Events (section 4.3) ----------------------------------------------------

Group("Events", function()
  local Events = ns.Events
  local seen
  Events:On("TEST_EVENT", function(value) seen = value end)
  Events:Fire("TEST_EVENT", 7)
  EQ(seen, 7, "fire passes arguments")
  Events:Fire("TEST_EVENT_UNKNOWN")
  OK(true, "fire without handlers does not error")
end)

-- --- Safe (section 4.2) -------------------------------------------------------

Group("Safe", function()
  local Safe = ns.Safe
  EQ(Safe.IsSecret("plain"), false, "no issecretvalue means not secret")
  EQ(Safe.Str("plain"), "plain", "Str keeps strings")
  EQ(Safe.Str(12), nil, "Str rejects numbers")
  EQ(Safe.Str(nil), nil, "Str rejects nil")
  issecretvalue = function(value) return value == SECRET end
  EQ(Safe.IsSecret(SECRET), true, "secret detected")
  EQ(Safe.Str(SECRET), nil, "Str rejects secret")
  issecretvalue = nil
end)

Group("Events isolation", function()
  local Events = ns.Events
  local reached = false
  local reported
  geterrorhandler = function() return function(err) reported = err end end
  Events:On("ISOLATION_TEST", function() error("boom") end)
  Events:On("ISOLATION_TEST", function() reached = true end)
  Events:Fire("ISOLATION_TEST")
  geterrorhandler = nil
  EQ(reached, true, "a failing handler does not stop the next one")
  OK(reported ~= nil and tostring(reported):find("boom", 1, true), "the failure is reported")
  Events:On("ISOLATION_TEST2", function() error("quiet") end)
  Events:Fire("ISOLATION_TEST2")
  OK(true, "a failure without an error handler is swallowed")
end)

-- --- Identity (section 6.1) ---------------------------------------------------

Group("Identity.Normalize", function()
  local Identity = ns.Identity
  EQ(Identity.Normalize("First Last"), "First Last", "plain name")
  EQ(Identity.Normalize("  First   Last  "), "First Last", "trim and collapse")
  EQ(Identity.Normalize("First\tLast"), "First Last", "tab collapses")
  EQ(Identity.Normalize("First Last-Realm"), "First Last", "realm suffix")
  EQ(Identity.Normalize("First Last - Realm"), "First Last", "spaced realm suffix")
  EQ(Identity.Normalize("First Last-Realm Name"), "First Last", "part after last hyphen")
  EQ(Identity.Normalize("Jürgen  Übel"), "Jürgen Übel", "utf-8 name")
  EQ(Identity.Normalize(""), nil, "empty text")
  EQ(Identity.Normalize("   "), nil, "blank text")
  EQ(Identity.Normalize(nil), nil, "nil text")
  EQ(Identity.Normalize(42), nil, "number")
  EQ(Identity.Normalize("-Realm"), nil, "realm only")
  issecretvalue = function(value) return value == SECRET end
  EQ(Identity.Normalize(SECRET), nil, "secret input")
  issecretvalue = nil
end)

Group("Identity keys", function()
  local Identity = ns.Identity
  EQ(Identity.Key("  First   Last-Realm "), "first last", "key is lowercased normalized name")
  EQ(Identity.Key(nil), nil, "key of nil")
  OK(Identity.Same("First Last", "first last-Realm"), "same ignores case and realm")
  OK(Identity.Same("First  Last", "First Last"), "same ignores spacing")
  OK(not Identity.Same("First Last", "First Other"), "different names")
  OK(not Identity.Same("First Last", nil), "nil is never the same")
end)

Group("Identity.FromUnit", function()
  local Identity = ns.Identity
  UnitName = function(unit)
    if unit == "player" then return "Self", "Char" end
    if unit == "target" then return "Target", nil end
    return nil
  end
  EQ(Identity.FromUnit("player"), "Self Char", "first and last name joined")
  EQ(Identity.FromUnit("target"), "Target", "single name")
  EQ(Identity.FromUnit("missing"), nil, "missing unit")
  EQ(Identity.Self(), "Self Char", "self name")
  UnitName = function() return SECRET, "Name" end
  issecretvalue = function(value) return value == SECRET end
  EQ(Identity.FromUnit("target"), nil, "secret first name")
  UnitName = function() return "Name", SECRET end
  EQ(Identity.FromUnit("target"), nil, "secret last name")
  UnitName = nil
  issecretvalue = nil
  EQ(Identity.FromUnit("player"), nil, "no UnitName")
  EQ(Identity.Self(), "?", "self falls back to ?")
end)

-- --- Settings (section 5) -----------------------------------------------------

Group("Settings.Init", function()
  local Settings = ns.Settings
  BlackbookDB = nil
  local db = Settings.Init()
  EQ(db.version, 1, "fresh database version")
  EQ(db.settings.language, "auto", "language default")
  EQ(db.settings.hideChat, true, "hideChat default")
  EQ(db.settings.autoDecline, true, "autoDecline default")
  EQ(db.settings.minimapAngle, 220, "minimapAngle default")
  EQ(db.settings.export.comments, true, "export.comments default")
  EQ(db.settings.community.friends.send, false, "friends.send default")
  EQ(db.settings.community.shareLabels.private_dispute, false, "private_dispute not shared")
  EQ(db.settings.community.shareLabels.other, false, "other not shared")
  EQ(db.settings.community.shareLabels.spam, true, "spam shared")
  EQ(db.settings.community.consentVersion, 0, "consent default")
  OK(type(db.settings.export.id) == "string" and #db.settings.export.id == 12
    and db.settings.export.id:match("^%x+$") ~= nil, "export id is 12 hex digits")
  EQ(type(db.records), "table", "records table created")
  EQ(type(db.subscriptions), "table", "subscriptions table created")
  EQ(type(db.community.reports), "table", "community reports table created")
  EQ(Settings.Init().settings.export.id, db.settings.export.id, "export id survives a reload")
end)

Group("Settings without math.randomseed", function()
  -- The WoW client has no math.randomseed. Reload the module so its seeding
  -- state is fresh, as on a first login.
  local saved = math.randomseed
  math.randomseed = nil
  local savedSettings, savedDb = ns.Settings, ns.db
  local chunk = assert(loadfile(root .. "/Blackbook/Core/Settings.lua"))
  chunk("Blackbook", ns)
  BlackbookDB = nil
  local ok, db = pcall(ns.Settings.Init)
  math.randomseed = saved
  OK(ok, "Init works when math.randomseed is missing")
  OK(ok and type(db.settings.export.id) == "string" and #db.settings.export.id == 12, "export id still generated")
  ns.Settings, ns.db = savedSettings, savedDb
end)

Group("Settings migration", function()
  local Settings = ns.Settings
  BlackbookDB = {
    version = 1,
    records = { ["a b"] = { name = "A B" } },
    settings = { language = "de" },
  }
  local db = Settings.Init()
  EQ(db.version, 1, "version stays 1")
  EQ(db.settings.language, "de", "existing value kept")
  EQ(db.settings.autoDecline, true, "missing value filled")
  EQ(db.records["a b"].name, "A B", "existing record kept")

  BlackbookDB = { records = {} }
  db = Settings.Init()
  EQ(db.version, 1, "unversioned data migrated")
  EQ(type(db.community and db.community.reports), "table", "community tables created by migration")

  BlackbookDB = { version = 99, settings = { language = "de" } }
  local state
  db, state = Settings.Init()
  EQ(db.version, 99, "newer data left alone")
  EQ(state, "newer", "newer data reported")
  EQ(ns.db, nil, "newer data is not exposed for writing")
  EQ(ns.Records.Save("First Last", "ignore", { scam = true }, "text"), nil, "no record saved into newer data")
  EQ(db.records, nil, "newer data gained no records table")
end)

Group("Settings accessors", function()
  local Settings = ns.Settings
  local Const = ns.Const
  BlackbookDB = nil
  Settings.Init()
  local fired = 0
  ns.Events:On(Const.Events.SETTINGS_CHANGED, function() fired = fired + 1 end)
  EQ(Settings.Get("community.friends.send"), false, "nested read")
  Settings.Set("community.friends.send", true)
  EQ(Settings.Get("community.friends.send"), true, "nested write")
  EQ(fired, 1, "Set fires SETTINGS_CHANGED")
  Settings.Set("export.name", "My list")
  EQ(Settings.Get("export.name"), "My list", "string value")
  EQ(Settings.Get("community.missing.key"), nil, "missing path")
  EQ(Settings.Get(""), nil, "empty path")
end)

-- --- Records (section 6.2) -----------------------------------------------------

Group("Records", function()
  local Records = ns.Records
  local Const = ns.Const
  BlackbookDB = nil
  ns.Settings.Init()
  local changed = 0
  ns.Events:On(Const.Events.RECORDS_CHANGED, function() changed = changed + 1 end)

  local record, err = Records.Save("First Last", "ignore", {}, "text")
  EQ(record, nil, "record without labels rejected")
  EQ(err, "ERR_LABELS", "label error key")
  record, err = Records.Save("First Last", "ignore", { scam = true }, "   ")
  EQ(err, "ERR_COMMENT", "empty comment rejected")
  record, err = Records.Save("First Last", "ignore", { scam = true }, string.rep("x", 256))
  EQ(err, "ERR_COMMENT_LENGTH", "long comment rejected")
  record, err = Records.Save("First Last", "bogus", { scam = true }, "text")
  EQ(err, "ERR_VERDICT", "bad verdict rejected")
  record, err = Records.Save("", "ignore", { scam = true }, "text")
  EQ(err, "ERR_NAME", "empty name rejected")
  EQ(changed, 0, "failed saves fire nothing")

  issecretvalue = function(value) return value == SECRET end
  record, err = Records.Save("Secret Guy", "ignore", { scam = true }, SECRET)
  EQ(err, "ERR_COMMENT", "secret comment rejected")
  issecretvalue = nil

  record = Records.Save("  First   Last-Realm ", "warn", { scam = true, unknown = true }, "  Met in a raid  ")
  OK(record ~= nil, "valid record saved")
  EQ(record.name, "First Last", "name normalized")
  EQ(record.comment, "Met in a raid", "comment trimmed")
  EQ(record.labels.scam, true, "label kept")
  EQ(record.labels.unknown, nil, "unknown label dropped")
  EQ(record.created, 1700000000, "created timestamp")
  EQ(record.updated, 1700000000, "updated timestamp")
  EQ(changed, 1, "save fires once")
  local found = Records.Get("first  last")
  EQ(found and found.name, "First Last", "lookup by name")

  local again = Records.Save("First Last", "ignore", { harassment = true }, "Changed my mind")
  EQ(again.created, 1700000000, "created kept on update")
  EQ(again.comment, "Changed my mind", "comment updated")
  EQ(again.verdict, "ignore", "verdict updated")
  EQ(again.labels.scam, nil, "labels replaced")
  EQ(changed, 2, "update fires once")

  Records.Save("Zed Zulu", "warn", { spam = true }, "Spam")
  local all = Records.All()
  EQ(#all, 2, "two records")
  EQ(all[1].name, "First Last", "sorted by name (1)")
  EQ(all[2].name, "Zed Zulu", "sorted by name (2)")
  EQ(Records.Remove("first last"), true, "remove existing")
  EQ(Records.Remove("first last"), false, "remove missing")
  EQ(#Records.All(), 1, "record removed")
  EQ(Records.Get("First Last"), nil, "lookup after removal")
end)

-- --- Resolver (section 6.3) ----------------------------------------------------

local function FreshDb()
  BlackbookDB = nil
  ns.Settings.Init()
  return ns.db
end

local function AddList(db, id, name, records, rules)
  db.subscriptions[id] = { id = id, name = name, author = "Some Author", records = records, rules = rules }
  ns.Events:Fire(ns.Const.Events.SUBSCRIPTIONS_CHANGED)
end

Group("Resolver", function()
  local Resolver = ns.Resolver
  local db = FreshDb()
  EQ(Resolver.Verdict("Nobody Here"), nil, "unknown player has no verdict")
  EQ(Resolver.Verdict(nil), nil, "nil name has no verdict")
  EQ(#Resolver.Sources("Nobody Here"), 0, "unknown player has no sources")

  ns.Records.Save("Own Warn", "warn", { scam = true }, "mine")
  local verdict, reasons = Resolver.Verdict("own warn-Realm")
  EQ(verdict, "warn", "own record verdict, name and realm normalized")
  EQ(reasons[1].source, "own", "own record is the reason")
  EQ(reasons[1].comment, "mine", "reason carries the comment")

  AddList(db, "aaaa", "List A", {
    ["own warn"] = { name = "Own Warn", labels = { scam = true } },
    ["list guy"] = { name = "List Guy", labels = { scam = true, spam = true } },
    ["plain guy"] = { name = "Plain Guy", labels = { hate = true } },
  }, { scam = "warn", spam = "ignore" })
  EQ(Resolver.Verdict("Own Warn"), "warn", "own record wins over a stronger list")
  EQ(#Resolver.Sources("Own Warn"), 1, "list is not consulted when an own record exists")
  verdict, reasons = Resolver.Verdict("List Guy")
  EQ(verdict, "ignore", "strongest rule among the labels of one entry")
  EQ(reasons[1].source, "list", "list reason")
  EQ(reasons[1].list, "List A", "list name in the reason")
  EQ(Resolver.Verdict("Plain Guy"), "notice", "no rule means notice")

  AddList(db, "bbbb", "List B", {
    ["plain guy"] = { name = "Plain Guy", labels = { hate = true } },
    ["list guy"] = { name = "List Guy", labels = { scam = true } },
  }, { hate = "warn" })
  EQ(Resolver.Verdict("Plain Guy"), "warn", "strongest verdict across lists")
  EQ(Resolver.Verdict("List Guy"), "ignore", "ignore from list A beats warn from list B")
  local sources = Resolver.Sources("List Guy")
  EQ(#sources, 2, "both lists are reported")
  EQ(sources[1].verdict, "ignore", "strongest reason first")

  AddList(db, "cccc", "List C", { ["bad rule"] = { name = "Bad Rule", labels = { scam = true } } },
    { scam = "bogus" })
  EQ(Resolver.Verdict("Bad Rule"), "notice", "unknown rule verdict is ignored")

  -- cache invalidation
  EQ(Resolver.Verdict("Late Add"), nil, "not listed yet")
  ns.Records.Save("Late Add", "ignore", { spam = true }, "now listed")
  EQ(Resolver.Verdict("Late Add"), "ignore", "RECORDS_CHANGED clears the cache")
  ns.Records.Remove("Late Add")
  EQ(Resolver.Verdict("Late Add"), nil, "removal clears the cache")
  EQ(Resolver.Verdict("Plain Guy"), "warn", "answer cached")
  db.subscriptions.bbbb.rules = { hate = "ignore" }
  EQ(Resolver.Verdict("Plain Guy"), "warn", "unannounced change keeps the cached answer")
  ns.Events:Fire(ns.Const.Events.SUBSCRIPTIONS_CHANGED)
  EQ(Resolver.Verdict("Plain Guy"), "ignore", "SUBSCRIPTIONS_CHANGED clears the cache")
  db.subscriptions.bbbb.rules = { hate = "warn" }
  ns.Events:Fire(ns.Const.Events.SETTINGS_CHANGED)
  EQ(Resolver.Verdict("Plain Guy"), "warn", "SETTINGS_CHANGED clears the cache")
  ns.Events:Fire(ns.Const.Events.COMMUNITY_CHANGED)
  OK(true, "COMMUNITY_CHANGED is accepted")
end)

-- --- Enforcement helpers ------------------------------------------------------

local printed = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, text) printed[#printed + 1] = text end }
local clock = 1000
GetTime = function() return clock end

Group("Chat filter", function()
  local Chat = ns.Chat
  local Settings = ns.Settings
  FreshDb()
  ns.Records.Save("Bad Actor", "ignore", { harassment = true }, "rude")
  ns.Records.Save("Mild Guy", "warn", { spam = true }, "spammy")

  EQ(Chat.Filter(nil, "CHAT_MSG_SAY", "hello", "Bad Actor-Realm"), true, "ignored player is hidden")
  EQ(Chat.Filter(nil, "CHAT_MSG_GUILD", "hello", "bad actor"), true, "case does not matter")
  EQ(Chat.Filter(nil, "CHAT_MSG_SAY", "hello", "Mild Guy"), false, "warned player is shown")
  EQ(Chat.Filter(nil, "CHAT_MSG_SAY", "hello", "Stranger One"), false, "unknown player is shown")
  EQ(Chat.Filter(nil, "CHAT_MSG_SAY", "hello", nil), false, "no author is shown")
  EQ(Chat.Filter(nil, "CHAT_MSG_SAY", nil, "Bad Actor"), false, "no text is left alone")

  issecretvalue = function(value) return value == SECRET end
  EQ(Chat.Filter(nil, "CHAT_MSG_SAY", "hello", SECRET), false, "secret author is left alone")
  EQ(Chat.Filter(nil, "CHAT_MSG_SAY", SECRET, "Bad Actor"), false, "secret text is left alone")
  issecretvalue = nil

  -- whisper notice throttle: the game calls the filter once per chat window
  printed = {}
  for _ = 1, 4 do Chat.Filter(nil, "CHAT_MSG_WHISPER", "psst", "Bad Actor") end
  EQ(#printed, 1, "four windows, one notice")
  OK(printed[1]:find("Bad Actor", 1, true), "notice names the player")
  clock = clock + 59
  Chat.Filter(nil, "CHAT_MSG_WHISPER", "psst", "Bad Actor")
  EQ(#printed, 1, "still throttled after 59 seconds")
  clock = clock + 2
  Chat.Filter(nil, "CHAT_MSG_WHISPER", "psst", "Bad Actor")
  EQ(#printed, 2, "a new notice after a minute")
  ns.Records.Save("Other Bad", "ignore", { spam = true }, "x")
  Chat.Filter(nil, "CHAT_MSG_WHISPER", "psst", "Other Bad")
  EQ(#printed, 3, "throttle is per person")
  Chat.Filter(nil, "CHAT_MSG_SAY", "hello", "Other Bad")
  EQ(#printed, 3, "only whispers produce a notice")

  Settings.Set("showNotices", false)
  clock = clock + 120
  printed = {}
  EQ(Chat.Filter(nil, "CHAT_MSG_WHISPER", "psst", "Bad Actor"), true, "still hidden without notices")
  EQ(#printed, 0, "showNotices off prints nothing")
  Settings.Set("showNotices", true)

  Settings.Set("hideChat", false)
  EQ(Chat.Filter(nil, "CHAT_MSG_SAY", "hello", "Bad Actor"), false, "hideChat off shows everything at once")
  Settings.Set("hideChat", true)
  EQ(Chat.Filter(nil, "CHAT_MSG_SAY", "hello", "Bad Actor"), true, "hideChat on again, no reload needed")

  -- registration
  local added = {}
  ChatFrame_AddMessageEventFilter = function(event, fn) added[#added + 1] = { event, fn } end
  EQ(Chat.Register(), true, "register succeeds")
  EQ(#added, #Chat.Events, "one filter per chat event")
  OK(added[1][2] == Chat.Filter, "the shared filter is installed")
  EQ(Chat.Register(), true, "second register is harmless")
  EQ(#added, #Chat.Events, "no double registration")
  ChatFrame_AddMessageEventFilter = nil
end)

Group("Requests", function()
  local Requests = ns.Requests
  local Settings = ns.Settings
  FreshDb()
  ns.Records.Save("Bad Actor", "ignore", { harassment = true }, "rude")
  ns.Records.Save("Mild Guy", "warn", { spam = true }, "spammy")

  local calls = {}
  local function Stub(name)
    _G[name] = function(...) calls[#calls + 1] = { name, ... } end
  end
  for _, name in ipairs({ "DeclineGroup", "DeclineGuild", "CancelDuel", "CancelTrade", "StaticPopup_Hide" }) do
    Stub(name)
  end
  local function Called(name)
    for _, call in ipairs(calls) do if call[1] == name then return call end end
    return nil
  end

  printed = {}
  EQ(Requests.Handle("PARTY_INVITE_REQUEST", "Bad Actor-Realm"), true, "party invite declined")
  OK(Called("DeclineGroup"), "DeclineGroup called")
  EQ(Called("StaticPopup_Hide")[2], "PARTY_INVITE", "invite popup hidden")
  OK(printed[1] and printed[1]:find("Bad Actor", 1, true), "decline notice names the player")

  calls = {}
  EQ(Requests.Handle("GUILD_INVITE_REQUEST", "Bad Actor", "Some Guild"), true, "guild invite declined")
  OK(Called("DeclineGuild"), "DeclineGuild called")
  EQ(Called("StaticPopup_Hide")[2], "GUILD_INVITE", "guild popup hidden")

  calls = {}
  EQ(Requests.Handle("DUEL_REQUESTED", "Bad Actor"), true, "duel declined")
  OK(Called("CancelDuel"), "CancelDuel called")
  EQ(Called("StaticPopup_Hide")[2], "DUEL_REQUESTED", "duel popup hidden")

  calls = {}
  UnitName = function(unit) if unit == "npc" then return "Bad", "Actor" end end
  EQ(Requests.Handle("TRADE_SHOW"), true, "trade declined")
  OK(Called("CancelTrade"), "CancelTrade called")
  EQ(Called("StaticPopup_Hide"), nil, "no popup for trades")
  UnitName = function(unit) if unit == "npc" then return "Mild", "Guy" end end
  calls = {}
  EQ(Requests.Handle("TRADE_SHOW"), false, "trade from a warned player is kept")
  UnitName = nil

  calls = {}
  EQ(Requests.Handle("PARTY_INVITE_REQUEST", "Mild Guy"), false, "warned player is not declined")
  EQ(Requests.Handle("PARTY_INVITE_REQUEST", "Stranger One"), false, "unknown player is not declined")
  EQ(Requests.Handle("PARTY_INVITE_REQUEST", nil), false, "no name is not declined")
  EQ(Requests.Handle("UNKNOWN_EVENT", "Bad Actor"), false, "unknown event ignored")
  issecretvalue = function(value) return value == SECRET end
  EQ(Requests.Handle("PARTY_INVITE_REQUEST", SECRET), false, "secret name is not declined")
  issecretvalue = nil
  EQ(#calls, 0, "nothing was called for the cases above")

  Settings.Set("autoDecline", false)
  EQ(Requests.Handle("PARTY_INVITE_REQUEST", "Bad Actor"), false, "autoDecline off declines nothing")
  EQ(#calls, 0, "no client call with autoDecline off")
  Settings.Set("autoDecline", true)

  printed = {}
  Settings.Set("showNotices", false)
  EQ(Requests.Handle("DUEL_REQUESTED", "Bad Actor"), true, "declined without notice")
  EQ(#printed, 0, "showNotices off prints nothing")
  Settings.Set("showNotices", true)

  DeclineGroup = nil
  EQ(Requests.Handle("PARTY_INVITE_REQUEST", "Bad Actor"), true, "a missing client function does not error")
  for _, name in ipairs({ "DeclineGuild", "CancelDuel", "CancelTrade", "StaticPopup_Hide" }) do _G[name] = nil end

  -- registration
  local frame = { events = {}, RegisterEvent = function(self, e) self.events[e] = true end,
    SetScript = function(self, _, fn) self.onEvent = fn end }
  CreateFrame = function() return frame end
  EQ(Requests.Register(), true, "register succeeds")
  OK(frame.events.PARTY_INVITE_REQUEST and frame.events.GUILD_INVITE_REQUEST
    and frame.events.DUEL_REQUESTED and frame.events.TRADE_SHOW, "all four events registered")
  Stub("DeclineGuild")
  calls = {}
  frame.onEvent(frame, "GUILD_INVITE_REQUEST", "Bad Actor")
  OK(Called("DeclineGuild"), "the registered handler declines")
  DeclineGuild = nil
  CreateFrame = nil
end)

-- --- Validation shared by editor and data layer (section 9) ------------------------

Group("Records.Check and CharCount", function()
  local Records, Identity = ns.Records, ns.Identity
  EQ(Identity.CharCount("abc"), 3, "ascii length")
  EQ(Identity.CharCount("Jürgen"), 6, "umlaut counts once")
  EQ(Identity.CharCount(""), 0, "empty text")
  EQ(Identity.CharCount(nil), 0, "nil text")
  EQ(Records.Check("First Last", "ignore", { scam = true }, "ok"), nil, "valid fields")
  EQ(Records.Check("", "ignore", { scam = true }, "ok"), "ERR_NAME", "empty name")
  EQ(Records.Check("First Last", "nope", { scam = true }, "ok"), "ERR_VERDICT", "bad verdict")
  EQ(Records.Check("First Last", "warn", {}, "ok"), "ERR_LABELS", "no labels")
  EQ(Records.Check("First Last", "warn", { unknown = true }, "ok"), "ERR_LABELS", "only unknown labels")
  EQ(Records.Check("First Last", "warn", { scam = true }, "  "), "ERR_COMMENT", "blank comment")
  EQ(Records.Check("First Last", "warn", { scam = true }, string.rep("x", 255)), nil, "255 characters fit")
  EQ(Records.Check("First Last", "warn", { scam = true }, string.rep("x", 256)), "ERR_COMMENT_LENGTH", "256 characters do not")
  EQ(Records.Check("First Last", "warn", { scam = true }, string.rep("ü", 255)), nil, "255 umlauts fit")
  EQ(Records.Check("First Last", "warn", { scam = true }, string.rep("ü", 256)), "ERR_COMMENT_LENGTH", "256 umlauts do not")
  FreshDb()
  OK(Records.Save("Umlaut Person", "warn", { scam = true }, string.rep("ü", 255)) ~= nil, "Save agrees with Check")
end)

-- --- Context menu (section 9) -----------------------------------------------------

local function StubRoot()
  local root = { items = {} }
  function root:CreateDivider() self.items[#self.items + 1] = { kind = "divider" } end
  function root:CreateTitle(text) self.items[#self.items + 1] = { kind = "title", text = text } end
  function root:CreateButton(text, fn) self.items[#self.items + 1] = { kind = "button", text = text, fn = fn } end
  return root
end

local function ButtonTexts(root)
  local texts = {}
  for _, item in ipairs(root.items) do
    if item.kind == "button" then texts[#texts + 1] = item.text end
  end
  return table.concat(texts, "|")
end

Group("Context menu", function()
  local ContextMenu, L = ns.ContextMenu, ns.L
  local db = FreshDb()
  UnitName = function(unit)
    if unit == "player" then return "Self", "Char" end
    if unit == "target" then return "Menu", "Target" end
    if unit == "npc" then return "Some", "Creature" end
  end
  UnitIsPlayer = function(unit) return unit ~= "npc" end

  local root = StubRoot()
  EQ(ContextMenu.Build(root, { unit = "target" }), true, "a player unit gets entries")
  EQ(root.items[1].kind, "divider", "a divider comes first")
  EQ(root.items[2].text, L.CTX_TITLE, "then the title")
  EQ(ButtonTexts(root), L.CTX_IGNORE .. "|" .. L.CTX_WARN .. "|" .. L.CTX_SEND, "new player: ignore, warn and send")

  root = StubRoot()
  EQ(ContextMenu.Build(root, { name = "Chat Guy-Realm" }), true, "a chat name gets entries")
  EQ(ButtonTexts(root), L.CTX_IGNORE .. "|" .. L.CTX_WARN .. "|" .. L.CTX_SEND, "name context works like a unit")

  root = StubRoot()
  EQ(ContextMenu.Build(root, { unit = "player" }), false, "own character gets nothing")
  EQ(#root.items, 0, "nothing added for the own character")
  root = StubRoot()
  EQ(ContextMenu.Build(root, { name = "self char-Realm" }), false, "own name from a chat menu gets nothing")
  root = StubRoot()
  EQ(ContextMenu.Build(root, { unit = "npc" }), false, "a non-player gets nothing")
  EQ(ContextMenu.Build(root, nil), false, "no context gets nothing")
  EQ(ContextMenu.Build(root, {}), false, "an empty context gets nothing")
  issecretvalue = function(value) return value == SECRET end
  EQ(ContextMenu.Build(root, { name = SECRET }), false, "a secret name gets nothing")
  issecretvalue = nil
  EQ(#root.items, 0, "nothing was added in the refused cases")

  -- existing record: edit and remove
  ns.Records.Save("Menu Target", "ignore", { scam = true }, "x")
  root = StubRoot()
  ContextMenu.Build(root, { unit = "target" })
  EQ(ButtonTexts(root), L.CTX_EDIT .. "|" .. L.CTX_REMOVE .. "|" .. L.CTX_SEND, "known player: edit, remove and send")
  local opened
  local realOpen = ns.Editor.Open
  ns.Editor.Open = function(name) opened = name end
  root.items[3].fn()
  EQ(opened, "Menu Target", "Edit opens the editor for that player")
  printed = {}
  root.items[4].fn()
  EQ(ns.Records.Get("Menu Target"), nil, "Remove deletes the record")
  OK(printed[1] and printed[1]:find("Menu Target", 1, true), "Remove says what it removed")

  -- player known only from an imported list: adopt
  AddList(db, "dddd", "Shared List", {
    ["menu target"] = { name = "Menu Target", labels = { scam = true }, comment = "from list" },
  }, { scam = "ignore" })
  root = StubRoot()
  ContextMenu.Build(root, { unit = "target" })
  EQ(ButtonTexts(root), L.CTX_IGNORE .. "|" .. L.CTX_WARN .. "|" .. L.CTX_ADOPT .. "|" .. L.CTX_SEND, "list-only player: adopt is offered")
  local verdictArg, prefillArg
  ns.Editor.Open = function(name, verdict, prefill) opened, verdictArg, prefillArg = name, verdict, prefill end
  root.items[5].fn()
  EQ(opened, "Menu Target", "Adopt opens the editor")
  EQ(verdictArg, "ignore", "adopt keeps the list's verdict")
  EQ(prefillArg.comment, "from list", "adopt prefills the comment")
  EQ(prefillArg.labels.scam, true, "adopt prefills the labels")
  root.items[3].fn()
  EQ(verdictArg, "ignore", "Ignore passes its verdict")
  root.items[4].fn()
  EQ(verdictArg, "warn", "Warn passes its verdict")
  ns.Editor.Open = realOpen

  -- registration
  local tags = {}
  Menu = { ModifyMenu = function(tag, fn) tags[tag] = fn end }
  EQ(ContextMenu.Register(), true, "register succeeds")
  OK(tags.MENU_UNIT_PLAYER and tags.MENU_UNIT_TARGET and tags.MENU_UNIT_FRIEND, "player menus hooked")
  root = StubRoot()
  tags.MENU_UNIT_TARGET(nil, root, { unit = "target" })
  OK(#root.items > 0, "the hook builds the entries")
  EQ(ContextMenu.Register(), true, "second register is harmless")
  Menu = nil
  UnitName, UnitIsPlayer = nil, nil
end)

Group("Context menu without the menu API", function()
  -- A fresh copy so the registered flag of the module above does not hide it.
  local chunk = assert(loadfile(root .. "/Blackbook/UI/ContextMenu.lua"))
  local saved = ns.ContextMenu
  chunk("Blackbook", ns)
  printed = {}
  EQ(ns.ContextMenu.Register(), false, "no Menu API: register reports failure")
  OK(printed[1] and printed[1]:find(ns.L.MSG_NO_MENU, 1, true), "a notice explains it")
  ns.ContextMenu = saved
end)

-- --- Widgets: dropdown path of the multi-select -------------------------------------

Group("MultiSelect dropdown", function()
  local Widgets = ns.Widgets
  local generator, caption
  local dropdown = {
    SetWidth = function() end,
    SetDefaultText = function(_, text) caption = text end,
    SetupMenu = function(_, fn) generator = fn end,
  }
  CreateFrame = function(_, _, _, template)
    if template == "WowStyle1DropdownTemplate" then return dropdown end
    return nil
  end
  MenuResponse = { Refresh = "refresh" }
  local changes = 0
  local picker = Widgets.MultiSelect({}, {
    { id = "a", text = "Item A" }, { id = "b", text = "Item B" },
  }, function() changes = changes + 1 end, {
    summary = function(selection) return next(selection) and "some" or "none" end,
  })
  OK(picker ~= nil and picker.frame == dropdown, "the dropdown is used when the client supports it")
  EQ(picker.height, 26, "dropdown height")
  EQ(caption, "none", "initial caption")

  local checkboxes = {}
  local root = { CreateCheckbox = function(_, text, isSelected, setSelected)
    checkboxes[#checkboxes + 1] = { text = text, isSelected = isSelected, setSelected = setSelected }
  end }
  generator(dropdown, root)
  EQ(#checkboxes, 2, "one checkbox per item")
  EQ(checkboxes[2].text, "Item B", "item text")
  EQ(checkboxes[2].isSelected(), false, "not selected at first")
  EQ(checkboxes[2].setSelected(), "refresh", "toggling keeps the menu open")
  EQ(checkboxes[2].isSelected(), true, "selected after toggling")
  EQ(changes, 1, "the change callback ran")
  EQ(caption, "some", "caption follows the selection")
  EQ(picker:Get().b, true, "Get returns the selection")
  picker:Set({ a = true })
  EQ(checkboxes[1].isSelected(), true, "Set selects")
  EQ(checkboxes[2].isSelected(), false, "Set clears the rest")
  local copy = picker:Get()
  copy.a = nil
  EQ(picker:Get().a, true, "Get returns a copy")
  checkboxes[1].setSelected()
  EQ(next(picker:Get()), nil, "toggling again deselects")
  EQ(caption, "none", "caption returns to the empty text")

  -- no dropdown template: the checkbox grid is used instead
  CreateFrame = function() return nil end
  EQ(Widgets.MultiSelect({}, { { id = "a", text = "Item A" } }, nil), nil, "without any frame support the picker is nil")
  MenuResponse = nil
  CreateFrame = nil
end)

-- --- Query: filter and sort (section 9) ---------------------------------------------

Group("Query", function()
  local Query = ns.Query
  local function R(name, verdict, labels, comment, updated)
    return { name = name, verdict = verdict, labels = labels, comment = comment, updated = updated }
  end
  local records = {
    R("Charlie", "ignore", { scam = true }, "stole my loot", 300),
    R("alice", "warn", { spam = true, scam = true }, "Advertising", 100),
    R("Bob", "ignore", { hate = true }, "rude in chat", 200),
    R("bob", "warn", { toxicity = true }, "second bob", 200),
  }
  local function Names(list)
    local names = {}
    for _, record in ipairs(list) do names[#names + 1] = record.name end
    return table.concat(names, ",")
  end
  local function LabelText(record)
    local ids = {}
    for id in pairs(record.labels or {}) do ids[#ids + 1] = id end
    table.sort(ids)
    return table.concat(ids, ", ")
  end

  EQ(Names(Query.Run(records, { labelText = LabelText })), "alice,Bob,bob,Charlie", "name sort ignores case, ties by exact name")
  EQ(Names(Query.Run(records, { sortKey = "name", descending = true, labelText = LabelText })), "Charlie,Bob,bob,alice", "descending reverses, equal names still ascend")
  EQ(Names(Query.Run(records, { verdict = "ignore" })), "Bob,Charlie", "verdict filter")
  EQ(Names(Query.Run(records, { verdict = "warn" })), "alice,bob", "verdict filter warn")
  EQ(Names(Query.Run(records, { labels = { scam = true } })), "alice,Charlie", "label filter")
  EQ(Names(Query.Run(records, { labels = { scam = true, hate = true } })), "alice,Bob,Charlie", "label filter matches any selected label")
  EQ(Names(Query.Run(records, { labels = {} })), "alice,Bob,bob,Charlie", "an empty label set filters nothing")
  EQ(Names(Query.Run(records, { search = "LOOT" })), "Charlie", "search matches comments ignoring case")
  EQ(Names(Query.Run(records, { search = "  bob  " })), "Bob,bob", "search is trimmed and matches names")
  EQ(Names(Query.Run(records, { search = "spam", labelText = LabelText })), "alice", "search matches label names")
  EQ(Names(Query.Run(records, { search = "a.c" })), "", "search is plain text, not a pattern")
  EQ(Names(Query.Run(records, { search = "zzz" })), "", "no match")
  EQ(Names(Query.Run(records, { search = "bob", verdict = "warn" })), "bob", "filters combine")
  EQ(Names(Query.Run(records, { sortKey = "date" })), "alice,Bob,bob,Charlie", "date sort, ties by name")
  EQ(Names(Query.Run(records, { sortKey = "date", descending = true })), "Charlie,Bob,bob,alice", "date descending, ties still by name")
  EQ(Names(Query.Run(records, { sortKey = "verdict" })), "alice,bob,Bob,Charlie", "verdict sort: warn before ignore")
  EQ(Names(Query.Run(records, { sortKey = "comment" })), "alice,Bob,bob,Charlie", "comment sort")
  EQ(Names(Query.Run(records, { sortKey = "labels", labelText = LabelText })), "Bob,Charlie,alice,bob", "labels sort uses the label text")
  EQ(#records, 4, "the input array is not modified")
  EQ(records[1].name, "Charlie", "the input order is kept")
  EQ(#Query.Run({}, {}), 0, "empty input")
  EQ(#Query.Run(records), 4, "no options")
end)

Group("TabList label text and Settings.SetLanguage", function()
  EQ(ns.TabList.LabelText({ labels = { scam = true, harassment = true } }),
    ns.L.LABEL_HARASSMENT .. ", " .. ns.L.LABEL_SCAM, "label names in label order")
  EQ(ns.TabList.LabelText({}), "", "no labels")
  FreshDb()
  EQ(ns.Settings.SetLanguage("de"), "de", "valid language")
  EQ(ns.Settings.Get("language"), "de", "language stored")
  EQ(ns.Settings.SetLanguage("xx"), nil, "invalid language")
  EQ(ns.Settings.Get("language"), "de", "invalid language changes nothing")
  EQ(ns.Settings.SetLanguage(nil), nil, "nil language")
  EQ(ns.Settings.SetLanguage("auto"), "auto", "auto is valid")
end)

-- --- Minimap geometry (section 9) ------------------------------------------------------

Group("Minimap geometry", function()
  local Minimap = ns.Minimap
  local x, y = Minimap.Position(0, 80)
  OK(math.abs(x - 80) < 1e-9 and math.abs(y) < 1e-9, "angle 0 is to the right")
  x, y = Minimap.Position(90, 80)
  OK(math.abs(x) < 1e-9 and math.abs(y - 80) < 1e-9, "angle 90 is up")
  x, y = Minimap.Position(225, 100)
  OK(math.abs(x + 70.710678) < 1e-5 and math.abs(y + 70.710678) < 1e-5, "angle 225 is down-left")
  EQ(Minimap.AngleFrom(1, 0), 0, "right is 0")
  EQ(Minimap.AngleFrom(0, 1), 90, "up is 90")
  EQ(Minimap.AngleFrom(-1, 0), 180, "left is 180")
  EQ(Minimap.AngleFrom(0, -1), 270, "down is 270")
  EQ(Minimap.AngleFrom(-1, -1), 225, "down-left is 225")
  EQ(Minimap.AngleFrom(1, -0.0001), 0, "slightly below right rounds to 0, never 360")
  for angle = 0, 359, 15 do
    local px, py = Minimap.Position(angle, 50)
    EQ(Minimap.AngleFrom(px, py), angle, "round trip of angle " .. angle)
  end
end)

-- --- Widgets.List (scroll box) ---------------------------------------------------------

Group("Widgets.List", function()
  local Widgets = ns.Widgets
  EQ(Widgets.List({}, 20, function() end), nil, "no scroll box support gives nil")

  local view, box, provider, retained
  local function NewWidget() return setmetatable({}, { __index = function() return function() end end }) end
  CreateFrame = function(_, _, _, template)
    if template == "WowScrollBoxList" then
      box = NewWidget()
      box.SetDataProvider = function(_, p, retain) provider, retained = p, retain end
      return box
    end
    return NewWidget()
  end
  CreateScrollBoxListLinearView = function()
    view = { SetElementExtent = function(_, extent) view.extent = extent end,
      SetElementInitializer = function(_, kind, fn) view.kind, view.init = kind, fn end }
    return view
  end
  CreateDataProvider = function(array) return { data = array } end
  ScrollUtil = { InitScrollBoxListWithScrollBar = function() end }
  ScrollBoxConstants = { RetainScrollPosition = "retain" }

  local setups = 0
  local list = Widgets.List({}, 22, function() setups = setups + 1 end)
  OK(list ~= nil and list.frame ~= nil, "the list is built")
  EQ(view.extent, 22, "row height is passed on")
  EQ(view.kind, "Button", "rows are buttons")
  list:SetData({ 1, 2, 3 })
  EQ(#provider.data, 3, "data reaches the provider")
  EQ(retained, "retain", "the scroll position is retained")
  view.init({}, 1)
  EQ(setups, 1, "the row setup function is the initializer")

  ScrollBoxConstants = nil
  list:SetData({ 1 })
  EQ(retained, nil, "without the constant the call still works")

  CreateFrame, CreateScrollBoxListLinearView, CreateDataProvider, ScrollUtil = nil, nil, nil, nil
end)

-- --- Markers and chat icons (section 6.6) -----------------------------------------------

Group("Markers", function()
  local Markers = ns.Markers
  EQ(Markers.Icon("warn"), "|TInterface/DialogFrame/UI-Dialog-Icon-AlertNew:0|t", "warn icon")
  EQ(Markers.Icon("warn", 16), "|TInterface/DialogFrame/UI-Dialog-Icon-AlertNew:16|t", "warn icon with a size")
  EQ(Markers.Icon("notice"), "|TInterface/Buttons/Arrow-Down-Up:0:0:0:0:32:32:0:32:0:32:77:153:255|t", "tinted notice arrow")
  OK(Markers.Icon("ignore"):find("|cffe61a1a", 1, true) and Markers.Icon("ignore"):find("|r", 1, true), "ignore is a red cross")
  EQ(Markers.Icon("bogus"), "", "unknown verdict has no icon")
  EQ(Markers.Icon(nil), "", "nil verdict has no icon")
  for _, verdict in ipairs({ "ignore", "warn", "notice" }) do
    OK(type(Markers.Look[verdict].color) == "table", verdict .. " has a tooltip colour")
  end
end)

Group("Chat markers", function()
  local Chat, Markers, Settings = ns.Chat, ns.Markers, ns.Settings
  local db = FreshDb()
  ns.Records.Save("Mild Guy", "warn", { spam = true }, "spammy")
  ns.Records.Save("Bad Actor", "ignore", { harassment = true }, "rude")
  AddList(db, "eeee", "Marker List", { ["list only"] = { name = "List Only", labels = { hate = true } } }, {})

  local hide, text, who, extra = Chat.Filter(nil, "CHAT_MSG_SAY", "hello", "Mild Guy-Realm", "arg3", 7)
  EQ(hide, false, "a warned player is not hidden")
  EQ(text, Markers.Icon("warn") .. " hello", "the warning icon is put in front of the text")
  EQ(who, "Mild Guy-Realm", "the author is passed on unchanged")
  EQ(extra, "arg3", "later arguments are passed on")
  hide, text = Chat.Filter(nil, "CHAT_MSG_GUILD", "hi", "List Only")
  EQ(text, Markers.Icon("notice") .. " hi", "a list-only player gets the notice icon")

  hide, text = Chat.Filter(nil, "CHAT_MSG_SAY", "hello", "Stranger One")
  EQ(hide, false, "an unknown player is not hidden")
  EQ(text, nil, "an unknown player's text is not replaced")
  EQ(select("#", Chat.Filter(nil, "CHAT_MSG_SAY", "hello", "Stranger One")), 1, "nothing extra is returned for an unknown player")

  Settings.Set("hideChat", false)
  hide, text = Chat.Filter(nil, "CHAT_MSG_SAY", "hello", "Bad Actor")
  EQ(hide, false, "an ignored player is shown when hiding is off")
  EQ(text, Markers.Icon("ignore") .. " hello", "and carries the red cross")
  Settings.Set("hideChat", true)
  EQ(Chat.Filter(nil, "CHAT_MSG_SAY", "hello", "Bad Actor"), true, "hiding on again")

  issecretvalue = function(value) return value == SECRET end
  hide, text = Chat.Filter(nil, "CHAT_MSG_SAY", SECRET, "Mild Guy")
  EQ(text, nil, "secret text is never rewritten")
  hide, text = Chat.Filter(nil, "CHAT_MSG_SAY", "hello", SECRET)
  EQ(text, nil, "a secret author is never rewritten")
  issecretvalue = nil
end)

-- --- Portrait overlay (section 6.6) -----------------------------------------------------

local function StubWidget()
  local widget = {}
  widget.Show = function(self) self.shown = true end
  widget.Hide = function(self) self.shown = false end
  widget.IsShown = function(self) return self.shown == true end
  widget.GetWidth = function() return 64 end
  widget.GetFrameLevel = function() return 1 end
  widget.SetTexture = function(self, texture) self.texture = texture end
  widget.SetVertexColor = function(self, r, g, b) self.tint = { r, g, b } end
  widget.CreateTexture = function() return StubWidget() end
  widget.RegisterEvent = function(self, event) self.events = self.events or {}; self.events[event] = true end
  widget.SetScript = function(self, name, fn) self.scripts = self.scripts or {}; self.scripts[name] = fn end
  return setmetatable(widget, { __index = function(_, key)
    if type(key) == "string" and key:match("^%u") then return function() end end
  end })
end

Group("Portrait", function()
  local Portrait, Markers = ns.Portrait, ns.Markers
  local db = FreshDb()
  EQ(Portrait.Update(), nil, "no target frame: nothing happens")
  EQ(Portrait.Register(), false, "no target frame: register reports failure")

  local created, allFrames = {}, {}
  TargetFrame = StubWidget()
  TargetFrame.TargetFrameContainer = { Portrait = StubWidget() }
  CreateFrame = function(_, name)
    local widget = StubWidget()
    if name then created[name] = widget end
    allFrames[#allFrames + 1] = widget
    return widget
  end
  local target
  UnitExists = function(unit) return unit == "target" and target ~= nil end
  UnitIsPlayer = function(unit) return target ~= nil and target.player ~= false end
  UnitName = function(unit)
    if unit == "target" and target then return target.first, target.last end
  end

  target = { first = "Marked", last = "Target" }
  EQ(Portrait.Update(), nil, "a player without a flag shows nothing")
  local overlay = created.BlackbookTargetMark
  OK(overlay ~= nil and not overlay:IsShown(), "the overlay exists and is hidden")

  ns.Records.Save("Marked Target", "ignore", { scam = true }, "x")
  EQ(Portrait.Update(), "ignore", "ignored target")
  OK(overlay:IsShown() and overlay.strike:IsShown() and not overlay.icon:IsShown(), "ignore draws the strike only")

  ns.Records.Save("Marked Target", "warn", { scam = true }, "x")
  EQ(Portrait.Update(), "warn", "warned target")
  OK(overlay:IsShown() and overlay.icon:IsShown() and not overlay.strike:IsShown(), "warn draws the corner icon only")
  EQ(overlay.icon.texture, Markers.Look.warn.icon, "warn icon texture")
  EQ(overlay.icon.tint[1], 1, "warn icon is not tinted")

  ns.Records.Remove("Marked Target")
  AddList(db, "ffff", "Portrait List", { ["marked target"] = { name = "Marked Target", labels = { hate = true } } }, {})
  EQ(Portrait.Update(), "notice", "list-only target")
  EQ(overlay.icon.texture, Markers.Look.notice.icon, "notice icon texture")
  EQ(overlay.icon.tint[3], 1, "notice icon is tinted blue")

  target.player = false
  EQ(Portrait.Update(), nil, "a non-player target shows nothing")
  OK(not overlay:IsShown(), "and the overlay hides")
  target.player = true
  issecretvalue = function(value) return value == SECRET end
  target.first = SECRET
  EQ(Portrait.Update(), nil, "a secret name shows nothing")
  issecretvalue = nil
  target.first = "Marked"
  target = nil
  EQ(Portrait.Update(), nil, "no target shows nothing")

  -- registration: target changes and data changes both redraw
  EQ(Portrait.Register(), true, "register succeeds")
  local eventFrame
  for _, widget in ipairs(allFrames) do
    if widget.events and widget.events.PLAYER_TARGET_CHANGED then eventFrame = widget end
  end
  OK(eventFrame ~= nil, "the target change event is registered")
  ns.Records.Save("Marked Target", "ignore", { scam = true }, "x")
  target = { first = "Marked", last = "Target" }
  overlay:Hide()
  eventFrame.scripts.OnEvent(eventFrame, "PLAYER_TARGET_CHANGED")
  OK(overlay.strike:IsShown(), "a target change redraws the mark")
  target = nil
  ns.Events:Fire(ns.Const.Events.RECORDS_CHANGED)
  OK(not overlay:IsShown(), "a data change redraws the mark (target gone)")
  target = { first = "Marked", last = "Target" }
  ns.Records.Save("Marked Target", "warn", { scam = true }, "x")
  OK(overlay.icon:IsShown() and not overlay.strike:IsShown(), "a record change redraws the mark at once")
  ns.Records.Remove("Marked Target")
  db.subscriptions.ffff = nil
  ns.Events:Fire(ns.Const.Events.SUBSCRIPTIONS_CHANGED)
  OK(not overlay:IsShown(), "removing the flag clears the mark")

  TargetFrame, CreateFrame, UnitExists, UnitIsPlayer, UnitName = nil, nil, nil, nil, nil
end)

-- --- Tooltip (section 6.6) -------------------------------------------------------------

local function Reload(path)
  local chunk = assert(loadfile(root .. "/Blackbook/" .. path))
  chunk("Blackbook", ns)
end

Group("Tooltip lines", function()
  local Tooltip, L = ns.Tooltip, ns.L
  local db = FreshDb()
  EQ(Tooltip.Lines("Nobody Here"), nil, "no lines without a verdict")

  ns.Records.Save("Tip Target", "ignore", { harassment = true, scam = true }, 'He said "hi" | bye')
  local lines = Tooltip.Lines("Tip Target")
  EQ(#lines, 3, "header, labels, comment")
  OK(lines[1].text:find("Blackbook: ", 1, true) and lines[1].text:find(L.VERDICT_IGNORE, 1, true), "header names the verdict")
  OK(lines[1].text:find("|cffe61a1a", 1, true), "header carries the verdict icon")
  EQ(lines[1].color[1], 1, "header uses the verdict colour")
  EQ(lines[2].text, L.LABEL_HARASSMENT .. ", " .. L.LABEL_SCAM, "labels line")
  EQ(lines[3].text, '"He said "hi" || bye"', "the comment is quoted and the pipe escaped")
  EQ(lines[3].wrap, true, "the comment wraps")

  ns.Records.Save("Pipe Label", "warn", { spam = true }, "||already||")
  EQ(Tooltip.Lines("Pipe Label")[3].text, '"||||already||||"', "every pipe in a comment is doubled")

  -- imported lists: source line, labels, comment; at most three lists
  local rules = { hate = "warn" }
  for index = 1, 5 do
    local id = "list" .. index
    db.subscriptions[id] = { id = id, name = "List " .. index .. "|x", author = "Author " .. index,
      records = { ["list guy"] = { name = "List Guy", labels = { hate = true }, comment = "from " .. index } },
      rules = rules }
  end
  ns.Events:Fire(ns.Const.Events.SUBSCRIPTIONS_CHANGED)
  lines = Tooltip.Lines("List Guy")
  local sources = 0
  for _, line in ipairs(lines) do
    if line.text:find("Imported list:", 1, true) then sources = sources + 1 end
  end
  EQ(sources, 3, "at most three lists are shown")
  OK(lines[2].text:find("List 1||x", 1, true), "list names are escaped")
  OK(lines[1].text:find(L.VERDICT_WARN, 1, true), "the header shows the effective verdict")
  EQ(#lines, 1 + 3 * 3, "header plus three lists of three lines")

  -- own record first, no list lines (own wins)
  ns.Records.Save("List Guy", "ignore", { spam = true }, "mine")
  lines = Tooltip.Lines("List Guy")
  EQ(#lines, 3, "an own record replaces the list lines")
end)

Group("Tooltip hook", function()
  local L = ns.L
  FreshDb()
  ns.Records.Save("Tip Target", "warn", { spam = true }, "hooked")

  local added, shown = {}, 0
  local function MakeTooltip(unit)
    local tooltip = { lines = added }
    tooltip.GetUnit = function() return "Tip Target", unit end
    tooltip.AddLine = function(_, text, r, g, b, wrap) added[#added + 1] = { text, r, g, b, wrap } end
    tooltip.Show = function() shown = shown + 1 end
    return tooltip
  end

  -- modern hook
  Reload("Display/Tooltip.lua")
  local callback
  TooltipDataProcessor = { AddTooltipPostCall = function(kind, fn) callback = fn; added.kind = kind end }
  Enum = { TooltipDataType = { Unit = "unit-type" } }
  GameTooltip = MakeTooltip("mouseover")
  UnitName = function() return "Tip", "Target" end
  UnitIsPlayer = function() return true end
  EQ(ns.Tooltip.Register(), true, "modern hook registers")
  EQ(added.kind, "unit-type", "registered for unit tooltips")
  callback(GameTooltip)
  OK(#added >= 3 and added[1][1]:find(L.VERDICT_WARN, 1, true), "lines are added for a flagged player")
  EQ(shown, 1, "the tooltip is shown again to resize it")

  added = {}
  GameTooltip.lines = added
  callback(MakeTooltip("mouseover"))
  EQ(#added, 0, "another tooltip object is left alone")
  UnitIsPlayer = function() return false end
  callback(GameTooltip)
  EQ(#added, 0, "a non-player unit is left alone")
  UnitIsPlayer = function() return true end
  issecretvalue = function(value) return value == SECRET end
  GameTooltip.GetUnit = function() return "Tip Target", SECRET end
  callback(GameTooltip)
  EQ(#added, 0, "a secret unit token is left alone")
  issecretvalue = nil
  GameTooltip.GetUnit = function() return "Tip Target", "mouseover" end
  UnitName = function() return "Stranger", "One" end
  callback(GameTooltip)
  EQ(#added, 0, "an unflagged player is left alone")

  -- older hook
  Reload("Display/Tooltip.lua")
  TooltipDataProcessor, Enum = nil, nil
  local hooked
  GameTooltip.HookScript = function(_, script, fn) hooked = { script, fn } end
  EQ(ns.Tooltip.Register(), true, "fallback hook registers")
  EQ(hooked[1], "OnTooltipSetUnit", "fallback uses the unit script")

  -- no hook at all
  Reload("Display/Tooltip.lua")
  GameTooltip.HookScript = nil
  printed = {}
  EQ(ns.Tooltip.Register(), false, "no hook: register reports failure")
  OK(printed[1] and printed[1]:find(L.MSG_NO_TOOLTIP, 1, true), "and says so")

  GameTooltip, UnitName, UnitIsPlayer = nil, nil, nil
  Reload("Display/Tooltip.lua")
end)

-- --- Sharing: Wire (section 7.1, 7.2) -------------------------------------------------

Group("Wire", function()
  local Wire = ns.Wire

  -- Base64: known vectors and a round trip of every length 0..10 with every byte value.
  EQ(Wire.Base64Encode(""), "", "base64 of nothing")
  EQ(Wire.Base64Encode("f"), "Zg==", "base64 one byte")
  EQ(Wire.Base64Encode("fo"), "Zm8=", "base64 two bytes")
  EQ(Wire.Base64Encode("foo"), "Zm9v", "base64 three bytes")
  EQ(Wire.Base64Encode("foobar"), "Zm9vYmFy", "base64 six bytes")
  for length = 0, 10 do
    local bytes = {}
    for index = 1, length do bytes[index] = string.char((index * 37 + length * 11) % 256) end
    local data = table.concat(bytes)
    EQ(Wire.Base64Decode(Wire.Base64Encode(data)), data, "base64 round trip, length " .. length)
  end
  local allBytes = {}
  for value = 0, 255 do allBytes[#allBytes + 1] = string.char(value) end
  local everything = table.concat(allBytes)
  EQ(Wire.Base64Decode(Wire.Base64Encode(everything)), everything, "base64 round trip of every byte value")

  EQ(Wire.Base64Decode("Zm9"), nil, "base64: length not a multiple of 4")
  EQ(Wire.Base64Decode("Zm9!"), nil, "base64: character outside the alphabet")
  EQ(Wire.Base64Decode("Zg==Zg=="), nil, "base64: padding in the middle")
  EQ(Wire.Base64Decode("Zg=a"), nil, "base64: padding followed by data")
  EQ(Wire.Base64Decode("Zm9v\n"), nil, "base64: whitespace is the caller's job")
  EQ(Wire.Base64Decode(nil), nil, "base64: not a string")

  -- Escaping.
  local tricky = "a\tb\nc\\d\\t end"
  EQ(Wire.Unescape(Wire.Escape(tricky)), tricky, "escape round trip")
  OK(not Wire.Escape(tricky):find("[\t\n]"), "an escaped field has no TAB or newline")
  EQ(Wire.Escape("one\r\ntwo"), "one\\ntwo", "a carriage return is dropped")
  EQ(Wire.Unescape("keep\\x"), "keepx", "an unknown escape keeps the character")
  local fields = Wire.Split(Wire.Line("R", "Name", "", "tab\there", 5))
  EQ(#fields, 5, "a line splits into its fields")
  EQ(Wire.Unescape(fields[4]), "tab\there", "a field with a TAB survives")
  EQ(fields[3], "", "an empty field stays empty")
  EQ(#Wire.Split(""), 1, "an empty line is one empty field")

  -- Adler-32.
  EQ(Wire.Checksum("Wikipedia"), "11e60398", "adler-32 known value")
  EQ(Wire.Checksum(""), "00000001", "adler-32 of nothing")
  local long = string.rep("z", 100000)
  EQ(#Wire.Checksum(long), 8, "adler-32 of a long text stays 8 digits")

  -- Truncation never splits a character.
  EQ(Wire.Truncate("short", 10), "short", "short text is unchanged")
  EQ(Wire.Truncate("abcdef", 3), "abc", "plain text is cut at the limit")
  EQ(Wire.Truncate("a\195\169b", 2), "a", "a two-byte character is not split")
  EQ(Wire.Truncate("a\195\169b", 3), "a\195\169", "a whole character fits")
end)

-- --- Sharing: Codec (section 7) ----------------------------------------------------------

local function MakeCode(payload, mode)
  return "BK1" .. (mode or "R") .. ":" .. ns.Wire.Base64Encode(payload) .. ":" .. ns.Wire.Checksum(payload)
end

local HEADER = "H\t1\tabc123\tTest list\tAuthor One\t1700000000"

Group("Codec", function()
  local Codec, Wire, Const = ns.Codec, ns.Wire, ns.Const
  C_EncodingUtil = nil

  local list = {
    id = "a1b2c3d4e5f6", name = "My \"list\"\twith tab", author = "Alice One", exported = 1700000123,
    records = {
      { name = "Bad Guy", verdict = "ignore", labels = { toxicity = true, scam = true },
        created = 1690000000, comment = "line one\nline two\\ with \195\188mlaut" },
      { name = "Other Guy", verdict = "warn", labels = { spam = true }, created = 1691000000, comment = "spam" },
      { name = "No Labels", verdict = "warn", labels = {}, comment = "skipped" },
    },
  }
  local code, count = Codec.Encode(list)
  EQ(count, 2, "a record without labels is skipped")
  OK(code:find("^BK1R:[A-Za-z0-9+/=]+:%x%x%x%x%x%x%x%x$") ~= nil, "uncompressed code layout")

  local back, err = Codec.Decode(code)
  OK(back ~= nil, "round trip decodes (" .. tostring(err) .. ")")
  EQ(back.id, "a1b2c3d4e5f6", "id survives")
  EQ(back.name, "My \"list\" with tab", "a TAB in the name becomes a space")
  EQ(back.author, "Alice One", "author survives")
  EQ(back.exported, 1700000123, "export time survives")
  EQ(back.count, 2, "count of records")
  local bad = back.records["bad guy"]
  EQ(bad.name, "Bad Guy", "record name survives")
  EQ(bad.comment, "line one line two\\ with \195\188mlaut", "newline becomes a space, backslash and umlaut survive")
  OK(bad.labels.toxicity and bad.labels.scam and not bad.labels.spam, "labels survive")
  EQ(bad.created, 1690000000, "created survives")
  EQ(bad.verdictHint, "ignore", "verdict hint survives")
  EQ(back.records["other guy"].verdictHint, "warn", "second hint")
  EQ(back.records["no labels"], nil, "the unlabelled record is not in the list")

  -- Line-wrapped and indented codes (chat tools add whitespace).
  local wrapped = code:gsub("(" .. string.rep(".", 20) .. ")", "%1\n  ")
  OK(Codec.Decode(wrapped) ~= nil, "whitespace and line breaks are ignored")
  OK(Codec.Decode("  \t" .. code .. "\r\n") ~= nil, "surrounding whitespace is ignored")

  -- Damaged codes.
  local _, e = Codec.Decode(nil)
  EQ(e, "ERR_CODE_EMPTY", "nil input")
  _, e = Codec.Decode(" \n ")
  EQ(e, "ERR_CODE_EMPTY", "blank input")
  _, e = Codec.Decode("hello world")
  EQ(e, "ERR_CODE_FORMAT", "not a code at all")
  _, e = Codec.Decode(code:sub(1, #code - 12))
  EQ(e, "ERR_CODE_FORMAT", "a code cut short loses its checksum")
  _, e = Codec.Decode(code:sub(1, 20) .. code:sub(22))
  EQ(e, "ERR_CODE_BASE64", "a character missing from the middle")
  local body, crc = code:match("^BK1R:(.-):(%x+)$")
  local flipped = body:sub(1, 10) .. (body:sub(11, 11) == "A" and "B" or "A") .. body:sub(12)
  _, e = Codec.Decode("BK1R:" .. flipped .. ":" .. crc)
  EQ(e, "ERR_CODE_CHECKSUM", "a changed character fails the checksum")
  _, e = Codec.Decode("BK1R:" .. body .. ":" .. (crc:sub(1, 7) .. (crc:sub(8) == "0" and "1" or "0")))
  EQ(e, "ERR_CODE_CHECKSUM", "a changed checksum fails")
  _, e = Codec.Decode("BK2R:" .. body .. ":" .. crc)
  EQ(e, "ERR_CODE_VERSION", "a newer code version is named")
  _, e = Codec.Decode(string.rep("A", Const.Limits.codeBytes + 1))
  EQ(e, "ERR_CODE_TOO_BIG", "oversized input is refused before any work")
  _, e = Codec.Decode(MakeCode(string.rep("x", Const.Limits.payloadBytes + 1)))
  EQ(e, "ERR_CODE_TOO_BIG", "an oversized payload is refused")

  -- Header rules.
  local function Err(payload) local _, key, line = Codec.Decode(MakeCode(payload)); return key, line end
  EQ(Err(""), "ERR_CODE_HEADER", "empty payload")
  EQ(Err("R\tName\t\t1\t\tx"), "ERR_CODE_HEADER", "no header line")
  EQ(Err("H\t2\tabc123\tT\tA\t1"), "ERR_CODE_HEADER", "header version 2")
  EQ(Err("H\t1\tABC123\tT\tA\t1"), "ERR_CODE_HEADER", "list id must be lower-case hex")
  EQ(Err("H\t1\tabc12g\tT\tA\t1"), "ERR_CODE_HEADER", "list id must be hex")
  EQ(Err("H\t1\t\tT\tA\t1"), "ERR_CODE_HEADER", "list id must not be empty")
  EQ(Err("H\t1\t" .. string.rep("a", 33) .. "\tT\tA\t1"), "ERR_CODE_HEADER", "list id at most 32 characters")
  OK(Codec.Decode(MakeCode("H\t1\t" .. string.rep("a", 32) .. "\tT\tA\t1")) ~= nil, "a 32 character id is fine")
  EQ(Err("H\t1\tabc123\t\tA\t1"), "ERR_CODE_HEADER", "list name must not be empty")
  EQ(Err("H\t1\tabc123\tT\t\t1"), "ERR_CODE_HEADER", "author must not be empty")
  EQ(Err("H\t1\tabc123\t" .. string.rep("n", 61) .. "\tA\t1"), "ERR_CODE_HEADER", "list name at most 60 characters")
  OK(Codec.Decode(MakeCode("H\t1\tabc123\t" .. string.rep("n", 60) .. "\tA\t")) ~= nil, "60 characters and no date are fine")
  EQ(Err("H\t1\tabc123\tT\tA\tsoon"), "ERR_CODE_HEADER", "the export time must be a number")
  EQ(Err("H\t1\tabc123\tT\tA"), "ERR_CODE_HEADER", "header needs six fields")

  -- Record rules; the line number names the offender.
  local function Rec(fields) return HEADER .. "\n" .. fields end
  OK(Codec.Decode(MakeCode(Rec("R\tGood Name\t\t1\t\tfine"))) ~= nil, "a minimal record is accepted")
  local key, line = Err(Rec("R\tGood Name\t\t1\t\tfine\nR\tOops\t\t0\t\tx"))
  EQ(key, "ERR_CODE_RECORD", "the second record is bad")
  EQ(line, 3, "its line number is reported")
  EQ(Err(Rec("R\tName\t\t0\t\tx")), "ERR_CODE_RECORD", "label mask 0")
  EQ(Err(Rec("R\tName\t\t512\t\tx")), "ERR_CODE_RECORD", "label mask above 511")
  OK(Codec.Decode(MakeCode(Rec("R\tName\t\t511\t\tx"))) ~= nil, "label mask 511 is the largest")
  EQ(Err(Rec("R\tName\t\tabc\t\tx")), "ERR_CODE_RECORD", "label mask must be a number")
  EQ(Err(Rec("R\tName\t\t1.5\t\tx")), "ERR_CODE_RECORD", "label mask must be whole")
  EQ(Err(Rec("R\tName\t\t1\tyesterday\tx")), "ERR_CODE_RECORD", "created must be a number")
  EQ(Err(Rec("R\tName\t\t1\t-5\tx")), "ERR_CODE_RECORD", "created must not be negative")
  EQ(Err(Rec("R\t\t\t1\t\tx")), "ERR_CODE_RECORD", "empty name")
  EQ(Err(Rec("R\t|cffff0000Name|r\t\t1\t\tx")), "ERR_CODE_RECORD", "a colour code in a name")
  EQ(Err(Rec("R\t" .. string.rep("n", 61) .. "\t\t1\t\tx")), "ERR_CODE_RECORD", "name at most 60 characters")
  EQ(Err(Rec("R\tName\t\t1\t\t" .. string.rep("c", 256))), "ERR_CODE_RECORD", "comment at most 255 characters")
  OK(Codec.Decode(MakeCode(Rec("R\tName\t\t1\t\t" .. string.rep("c", 255)))) ~= nil, "a 255 character comment is fine")
  OK(Codec.Decode(MakeCode(Rec("R\tName\t\t1\t\t" .. string.rep("\195\188", 255)))) ~= nil, "umlauts count once")
  EQ(Err(Rec("R\tName\t\t1\tx")), "ERR_CODE_RECORD", "a record needs six fields")
  EQ(Err(Rec("X\tName\t\t1\t\tx")), "ERR_CODE_RECORD", "an unknown line type")
  local hinted = Codec.Decode(MakeCode(Rec("R\tName\tbogus\t1\t\tx")))
  EQ(hinted.records.name.verdictHint, nil, "an unknown verdict hint is dropped, not rejected")
  local dup = Codec.Decode(MakeCode(Rec("R\tSame Guy\t\t1\t\tfirst\nR\tsame guy\t\t2\t\tsecond")))
  EQ(dup.count, 1, "the same name twice counts once")
  EQ(dup.records["same guy"].comment, "second", "the later entry wins")
  local realm = Codec.Decode(MakeCode(Rec("R\tName-Realm\t\t1\t\tx")))
  OK(realm.records.name ~= nil, "a realm suffix is stripped from the name")

  local many = { HEADER }
  for index = 1, Const.Limits.recordsPerList + 1 do many[#many + 1] = "R\tPlayer" .. index .. "\t\t1\t\tx" end
  EQ(Err(table.concat(many, "\n")), "ERR_CODE_TOO_MANY", "more than 5000 records")
  table.remove(many)
  local full = Codec.Decode(MakeCode(table.concat(many, "\n")))
  OK(full ~= nil and full.count == Const.Limits.recordsPerList, "exactly 5000 records are accepted")

  -- Compression is optional and verified.
  C_EncodingUtil = {
    CompressString = function(text) return (text:gsub("record record record ", "\1")) end,
    DecompressString = function(text) return (text:gsub("\1", "record record record ")) end,
  }
  local squeezable = { id = "c0ffee", name = "Squeeze", author = "Alice One", exported = 1, records = {} }
  for index = 1, 6 do
    squeezable.records[index] = { name = "Packed Guy" .. string.char(64 + index), verdict = "warn",
      labels = { spam = true }, comment = string.rep("record record record ", 5) }
  end
  local packed = Codec.Encode(squeezable)
  OK(packed:find("^BK1C:") ~= nil, "a code is compressed when that makes it smaller")
  local unpacked = Codec.Decode(packed)
  OK(unpacked ~= nil and unpacked.count == 6, "a compressed code decodes")
  C_EncodingUtil = nil
  _, e = Codec.Decode(packed)
  EQ(e, "ERR_CODE_NOCOMPRESS", "a compressed code needs the client's decompression")
  C_EncodingUtil = { CompressString = function(text) return text:sub(1, #text - 5) end,
    DecompressString = function(text) return text end }
  OK(Codec.Encode(squeezable):find("^BK1R:") ~= nil, "compression that does not round trip is not used")
  C_EncodingUtil = { CompressString = function() error("boom") end, DecompressString = function() end }
  OK(Codec.Encode(squeezable):find("^BK1R:") ~= nil, "a failing compressor falls back to the raw code")
  C_EncodingUtil = { CompressString = function(text) return text .. text end, DecompressString = function(text) return text end }
  OK(Codec.Encode(squeezable):find("^BK1R:") ~= nil, "compression that grows the text is not used")
  C_EncodingUtil = { CompressString = function() end, DecompressString = function() error("bad data") end }
  _, e = Codec.Decode(MakeCode("zzz", "C"))
  EQ(e, "ERR_CODE_CORRUPT", "damaged compressed data is named")
  C_EncodingUtil = nil
end)

Group("Codec export of the own list", function()
  local Codec, Settings, Records = ns.Codec, ns.Settings, ns.Records
  local db = FreshDb()
  UnitName = function(unit) if unit == "player" then return "Alice", "One" end end
  C_EncodingUtil = nil

  Records.Save("Spammer One", "ignore", { spam = true }, "spam link")
  Records.Save("Mixed Two", "warn", { spam = true, scam = true }, "both")
  Records.Save("Toxic Three", "warn", { toxicity = true }, "toxic")

  local export = db.settings.export
  OK(export.id:match("^%x+$") ~= nil and #export.id == 12, "the export id is 12 hex digits")
  export.labels = { spam = true, scam = true } -- toxicity is not shared
  local code, count = Codec.ExportOwn()
  EQ(count, 2, "only records with a selected label are exported")
  local list = Codec.Decode(code)
  EQ(list.id, export.id, "the export id is the list id")
  EQ(list.author, "Alice One", "the author is the own character")
  EQ(list.name, "Alice's list", "the default list name uses the first name")
  OK(list.records["spammer one"] and list.records["mixed two"], "the right records are in")
  EQ(list.records["toxic three"], nil, "a record without a selected label is out")
  EQ(list.records["spammer one"].comment, "spam link", "comments are included by default")

  export.labels = { scam = true }
  list = Codec.Decode((Codec.ExportOwn()))
  OK(list.records["mixed two"].labels.scam and not list.records["mixed two"].labels.spam,
    "labels that are not selected are dropped from a record")
  EQ(list.count, 1, "only the record that still has a label stays")

  export.labels = { spam = true, scam = true }
  export.comments = false
  export.name = "Custom Name"
  list = Codec.Decode((Codec.ExportOwn()))
  EQ(list.records["spammer one"].comment, "", "comments can be left out")
  EQ(list.name, "Custom Name", "a configured list name is used")

  export.labels = { harassment = true }
  _, count = Codec.ExportOwn()
  EQ(count, 0, "nothing qualifies with an unrelated selection")
end)

-- --- Sharing: Subscriptions (section 7.3, 6.3) ----------------------------------------------

Group("Subscriptions", function()
  local Subs, Codec, Resolver, Records, Settings = ns.Subscriptions, ns.Codec, ns.Resolver, ns.Records, ns.Settings
  local db = FreshDb()
  UnitName = function(unit) if unit == "player" then return "Alice", "One" end end

  local function List(id, name, entries)
    local records = {}
    for _, entry in ipairs(entries) do
      records[string.lower(entry[1])] = { name = entry[1], labels = entry[2], comment = entry[3] or "c" }
    end
    return { id = id, name = name, author = "Bob Two", exported = 1700000000, records = records,
      count = #entries }
  end

  local changes = 0
  ns.Events:On("SUBSCRIPTIONS_CHANGED", function() changes = changes + 1 end)

  local sub, replaced = Subs.Import(List("aaaa", "Zed list", { { "Griefer One", { griefing = true } },
    { "Scammer Two", { scam = true, spam = true } }, { "Alice One", { spam = true } } }))
  OK(sub ~= nil, "a list imports")
  EQ(replaced, false, "it is new")
  EQ(sub.count, 2, "the player's own character is dropped from the list")
  EQ(sub.records["alice one"], nil, "no own entry in the stored records")
  EQ(changes, 1, "the import announces the change")
  EQ(Resolver.Verdict("Griefer One"), "notice", "no rule: an imported entry is a notice")

  -- Rules.
  EQ(Subs.Rule("aaaa", "griefing"), "notice", "the default rule is notice")
  OK(Subs.SetRule("aaaa", "griefing", "ignore"), "a rule is set")
  EQ(Resolver.Verdict("Griefer One"), "ignore", "the rule changes the effective verdict")
  OK(Subs.SetRule("aaaa", "scam", "warn"), "second rule")
  EQ(Resolver.Verdict("Scammer Two"), "warn", "the strongest label rule applies")
  OK(Subs.SetRule("aaaa", "spam", "ignore"), "a stronger rule on a second label")
  EQ(Resolver.Verdict("Scammer Two"), "ignore", "the strongest of the entry's labels wins")
  OK(Subs.SetRule("aaaa", "spam", "notice"), "back to the default")
  EQ(db.subscriptions.aaaa.rules.spam, nil, "the default is stored by removing the rule")
  EQ(Resolver.Verdict("Scammer Two"), "warn", "the other label's rule applies again")
  EQ(Subs.SetRule("aaaa", "nonsense", "warn"), false, "an unknown label is refused")
  EQ(Subs.SetRule("aaaa", "spam", "banish"), false, "an unknown verdict is refused")
  EQ(Subs.SetRule("missing", "spam", "warn"), false, "an unknown list is refused")

  -- Re-import keeps the rules and says it replaced.
  sub, replaced = Subs.Import(List("aaaa", "Zed list v2", { { "Griefer One", { griefing = true } } }))
  EQ(replaced, true, "the same id replaces the list")
  EQ(sub.rules.griefing, "ignore", "the rules are kept")
  EQ(db.subscriptions.aaaa.name, "Zed list v2", "the records are replaced")
  EQ(db.subscriptions.aaaa.records["scammer two"], nil, "entries that left the list are gone")
  EQ(Resolver.Verdict("Scammer Two"), nil, "and no longer flag the player")

  -- Own list id, own records, limits.
  local _, err = Subs.Import(List(Settings.Get("export.id"), "Mine", {}))
  EQ(err, "ERR_OWN_LIST", "your own list is refused")
  Records.Save("Griefer One", "warn", { toxicity = true }, "mine")
  EQ(Resolver.Verdict("Griefer One"), "warn", "an own record always wins over an imported rule")
  local entries = Subs.Entries()
  EQ(#entries, 1, "one imported entry")
  EQ(entries[1].verdict, "warn", "the entry shows the effective verdict")
  EQ(entries[1].own, true, "and says the player has an own record")
  EQ(entries[1].list, "Zed list v2", "and its list")

  Subs.Import(List("bbbb", "Alpha list", {}))
  local all = Subs.All()
  EQ(all[1].name, "Alpha list", "lists are sorted by name")
  EQ(all[2].name, "Zed list v2", "second list")
  for index = 1, 48 do Subs.Import(List(string.format("%04x", 0x1000 + index), "L" .. index, {})) end
  EQ(#Subs.All(), 50, "fifty lists fit")
  _, err = Subs.Import(List("ffff", "One too many", {}))
  EQ(err, "ERR_TOO_MANY_LISTS", "the fifty-first list is refused")
  OK(Subs.Import(List("aaaa", "Replacing is fine", {})), "replacing an existing list still works at the limit")

  local before = changes
  OK(Subs.Remove("aaaa"), "a list is removed")
  EQ(Subs.Remove("aaaa"), false, "removing it twice does nothing")
  EQ(changes, before + 1, "removal announces the change")
  EQ(Subs.Get("aaaa"), nil, "the list is gone")
  EQ(Subs.Rule("aaaa", "griefing"), "notice", "the rule of a missing list is the default")
end)

-- --- Sharing: in-game transfer (section 7.4) ---------------------------------------------------

Group("Transfer", function()
  local Transfer, Subs, Const, Wire = ns.Transfer, ns.Subscriptions, ns.Const, ns.Wire
  local L = ns.L
  C_EncodingUtil = nil

  -- A scripted clock and a recording transport.
  local now, timers, sent = 0, {}, {}
  local sendOk = true
  Transfer.io = {
    send = function(text, target)
      if not sendOk then return false end
      sent[#sent + 1] = { text = text, target = target }
      return true
    end,
    after = function(delay, fn) timers[#timers + 1] = { at = now + delay, fn = fn } end,
    now = function() return now end,
  }
  local function Advance(seconds)
    local limit = now + seconds
    while true do
      local pick
      for index, timer in ipairs(timers) do
        if timer.at <= limit and (not pick or timer.at < timers[pick].at) then pick = index end
      end
      if not pick then break end
      local timer = table.remove(timers, pick)
      now = math.max(now, timer.at)
      timer.fn()
    end
    now = limit
  end
  local function Take()
    local taken = sent
    sent = {}
    return taken
  end
  local function Me(first, last) UnitName = function(unit) if unit == "player" then return first, last end end end

  -- Popups.
  local popup, shown, hidden = nil, 0, 0
  StaticPopupDialogs = {}
  StaticPopup_Show = function(which, a, b) shown = shown + 1; popup = { which = which, a = a, b = b } end
  StaticPopup_Hide = function() hidden = hidden + 1 end

  local function Fresh()
    sendOk = true
    Advance(400) -- lets every earlier session, queue and rate limit run out
    FreshDb()
    Me("Alice", "One")
    sent, printed, popup, shown, hidden = {}, {}, nil, 0, 0
  end
  local function Printed(needle)
    for _, line in ipairs(printed) do
      if line:find(needle, 1, true) then return true end
    end
    return false
  end
  local function Fill(count)
    for index = 1, count do
      ns.Records.Save("Player" .. string.char(64 + index % 26 + 1) .. index, "warn",
        { spam = true }, "comment number " .. index .. " " .. string.rep("x", 40))
    end
  end
  local function Offer(id, parts, records, name)
    return table.concat({ "OFFER", id, parts, records, name }, "\t")
  end
  local function Deliver(text, sender, channel)
    Transfer.OnMessage(Const.TRANSFER_PREFIX, text, channel or "WHISPER", sender)
  end
  local function Fields(text) return Wire.Split(text) end

  -- Errors before anything is sent.
  Fresh()
  local ok, err = Transfer.Send("Alice One")
  EQ(err, "MSG_SELF", "you cannot send to yourself")
  ok, err = Transfer.Send("")
  EQ(err, "ERR_NAME", "a name is needed")
  ok, err = Transfer.Send("Bob Two")
  EQ(err, "ERR_EXPORT_EMPTY", "an empty list is not offered")
  EQ(#sent, 0, "nothing was sent")
  for index = 1, 400 do
    ns.Records.Save("Long" .. string.char(97 + index % 26) .. index, "warn", { spam = true },
      string.rep(string.char(33 + index % 90), 250))
  end
  ok, err = Transfer.Send("Bob Two")
  EQ(err, "ERR_TRANSFER_TOO_BIG", "a list above 600 parts is refused")
  EQ(#sent, 0, "and nothing was sent")

  -- A full transfer, Alice to Bob, with the identity switched between roles.
  Fresh()
  Fill(12)
  local aliceExportId = ns.db.settings.export.id
  ok = Transfer.Send("  Bob  Two ")
  OK(ok, "the offer is accepted for sending")
  local first = Take()
  EQ(#first, 1, "one message: the offer")
  EQ(first[1].target, "Bob Two", "it goes to the normalized name (spaces trimmed and collapsed)")
  local offer = Fields(first[1].text)
  EQ(offer[1], "OFFER", "an OFFER")
  EQ(#offer[2], 8, "with an 8 digit session id")
  local partCount, recordCount = tonumber(offer[3]), tonumber(offer[4])
  OK(partCount >= 2, "a list of twelve needs several parts (" .. partCount .. ")")
  EQ(recordCount, 12, "the record count")
  EQ(offer[5], "Alice's list", "the list name")
  OK(Printed("Offered your list to Bob Two"), "the sender is told the offer went out")
  local _, busyErr = Transfer.Send("Bob Two")
  EQ(busyErr, "ERR_TRANSFER_BUSY", "a second offer to the same player waits")

  Me("Bob", "Two")
  ns.db.settings.export.id = "bbbbbbbbbbbb"
  for key in pairs(ns.db.records) do ns.db.records[key] = nil end
  ns.Events:Fire("RECORDS_CHANGED")
  Deliver(first[1].text, "Alice One")
  EQ(shown, 1, "the receiver gets a popup")
  EQ(popup.which, "BLACKBOOK_TRANSFER_OFFER", "the popup is Blackbook's")
  OK(popup.a:find("Alice One", 1, true) ~= nil, "it names the sender")
  OK(popup.b:find("Alice's list", 1, true) ~= nil and popup.b:find("12", 1, true) ~= nil,
    "it names the list and its size")
  EQ(popup.which and StaticPopupDialogs.BLACKBOOK_TRANSFER_OFFER.timeout, 55, "the popup gives up before the sender does")
  EQ(#Take(), 0, "nothing is sent before the player answers")
  StaticPopupDialogs.BLACKBOOK_TRANSFER_OFFER.OnAccept()
  Advance(0.5)
  local reply = Take()
  EQ(#reply, 1, "accepting sends one message")
  EQ(reply[1].text, "ACCEPT\t" .. offer[2], "an ACCEPT for that session")
  EQ(reply[1].target, "Alice One", "to the sender")

  Me("Alice", "One")
  Deliver(reply[1].text, "Bob Two")
  Advance(0.3 * (partCount + 5))
  local parts = Take()
  EQ(#parts, partCount, "every part is sent")
  EQ(parts[1].target, "Bob Two", "to the receiver")
  for index, part in ipairs(parts) do
    local fields = Fields(part.text)
    OK(fields[1] == "PART" and fields[2] == offer[2] and tonumber(fields[3]) == index
      and #fields[4] <= Const.Limits.transferChunk and #fields[4] >= 1, "part " .. index .. " is well formed")
    OK(#part.text + #Const.TRANSFER_PREFIX <= 255, "part " .. index .. " fits an addon message")
  end
  OK(Printed("Sent your list to Bob Two"), "the sender is told it arrived")
  local _, again = Transfer.Send("Bob Two")
  OK(again ~= "ERR_TRANSFER_BUSY", "the session is closed, so the player is no longer busy")
  Take()

  -- Bob receives the parts, in reverse order.
  Me("Bob", "Two")
  printed = {}
  for index = #parts, 1, -1 do
    EQ(Subs.Get(aliceExportId), nil, "nothing is imported before the last part (" .. index .. ")")
    Deliver(parts[index].text, "Alice One")
  end
  local imported = Subs.Get(aliceExportId)
  OK(imported ~= nil, "the list is imported when the last part arrives")
  EQ(imported and imported.count, 12, "all records arrived")
  EQ(imported and imported.name, "Alice's list", "with its name")
  OK(Printed("Alice's list"), "the receiver is told")

  -- Declining.
  Fresh()
  Fill(3)
  Transfer.Send("Carol Three")
  local declined = Take()[1]
  local sessionId = Fields(declined.text)[2]
  Deliver("ACCEPT\tdeadbeef", "Carol Three")
  EQ(#Take(), 0, "an ACCEPT for another session is ignored")
  Deliver("DECLINE\t" .. sessionId, "Someone Else")
  OK(not Printed("did not take your list"), "a DECLINE from another player is ignored")
  Deliver("DECLINE\t" .. sessionId, "Carol Three")
  OK(Printed("Carol Three did not take your list"), "a DECLINE is reported")
  OK(Transfer.Send("Carol Three"), "and the player can be offered again")
  Take()

  -- No answer.
  Fresh()
  Fill(3)
  Transfer.Send("Dave Four")
  Take()
  Advance(59)
  OK(not Printed("did not answer"), "no timeout yet after 59 seconds")
  Advance(2)
  OK(Printed("Dave Four did not answer your offer"), "the offer times out after 60 seconds")
  Deliver("ACCEPT\tstale", "Dave Four")
  Advance(5)
  EQ(#Take(), 0, "a late ACCEPT sends nothing")
  OK(Transfer.Send("Dave Four"), "the player can be offered again")
  Take()

  -- Send failures retry, then give up once.
  Fresh()
  Fill(3)
  sendOk = false
  Transfer.Send("Erin Five")
  Advance(4)
  OK(not Printed("failed"), "no failure report while retries remain")
  Advance(3)
  OK(Printed("Sending your list to Erin Five failed"), "the failure is reported after 20 tries")
  local failures = 0
  for _, line in ipairs(printed) do if line:find("failed", 1, true) then failures = failures + 1 end end
  EQ(failures, 1, "the failure is reported once")
  sendOk = true
  OK(Transfer.Send("Erin Five"), "after a failure the player can be offered again")
  Take()

  -- Receiver validation.
  Fresh()
  Me("Bob", "Two")
  Deliver(Offer("1234abcd", 2, 5, "Good"), "Alice One", "GUILD")
  EQ(shown, 0, "only whispers count")
  Transfer.OnMessage("OTHER", Offer("1234abcd", 2, 5, "Good"), "WHISPER", "Alice One")
  EQ(shown, 0, "only our prefix counts")
  Deliver(Offer("1234abcd", 2, 5, "Good"), "Bob Two")
  EQ(shown, 0, "an offer from yourself is ignored")
  issecretvalue = function(value) return value == SECRET end
  Deliver(Offer("1234abcd", 2, 5, "Good"), SECRET)
  Transfer.OnMessage(Const.TRANSFER_PREFIX, SECRET, "WHISPER", "Alice One")
  issecretvalue = nil
  EQ(shown, 0, "secret values are ignored")
  for label, text in pairs({
    ["short session id"] = Offer("12ab", 2, 5, "x"),
    ["uppercase session id"] = Offer("1234ABCD", 2, 5, "x"),
    ["non-hex session id"] = Offer("1234abcz", 2, 5, "x"),
    ["zero parts"] = Offer("1234abcd", 0, 5, "x"),
    ["too many parts"] = Offer("1234abcd", 601, 5, "x"),
    ["fractional parts"] = Offer("1234abcd", 1.5, 5, "x"),
    ["too many records"] = Offer("1234abcd", 2, 5001, "x"),
    ["negative records"] = Offer("1234abcd", 2, -1, "x"),
    ["text parts"] = Offer("1234abcd", "two", 5, "x"),
    ["missing name field"] = "OFFER\t1234abcd\t2\t5",
    ["extra field"] = Offer("1234abcd", 2, 5, "x") .. "\textra",
    ["unknown word"] = "HELLO\t1234abcd",
  }) do
    Deliver(text, "Alice One")
    EQ(shown, 0, "malformed offer ignored: " .. label)
  end
  EQ(#Take(), 0, "malformed offers get no reply")

  -- An ignored sender is met with silence.
  ns.Records.Save("Spammer Six", "ignore", { spam = true }, "spam")
  Deliver(Offer("1234abcd", 2, 5, "Good"), "Spammer Six")
  EQ(shown, 0, "no popup for an ignored player")
  EQ(#Take(), 0, "and no reply either")

  -- A good offer; a second one while the popup is open is declined, but not repeatedly.
  Deliver(Offer("1234abcd", 2, 5, "Good\1Name"), "Alice One")
  EQ(shown, 1, "a good offer shows a popup")
  OK(popup.b:find("Good Name", 1, true) ~= nil and not popup.b:find("%c"), "control characters in a list name become spaces")
  Deliver(Offer("99999999", 2, 5, "Second"), "Carol Three")
  EQ(shown, 1, "a second offer while the popup is open shows no popup")
  Advance(0.5)
  local busy = Take()
  EQ(#busy, 1, "it is declined")
  EQ(busy[1].text, "DECLINE\t99999999", "with a DECLINE for its session")
  EQ(busy[1].target, "Carol Three", "to that player")
  Deliver(Offer("88888888", 2, 5, "Third"), "Carol Three")
  Advance(0.5)
  EQ(#Take(), 0, "repeated offers from the same player are not answered again within 10 seconds")
  Advance(11)
  Deliver(Offer("77777777", 2, 5, "Fourth"), "Carol Three")
  Advance(0.5)
  EQ(#Take(), 1, "after 10 seconds it is answered again")

  -- Parts before accepting are ignored, then the rules of a part.
  Deliver("PART\t1234abcd\t1\tAAAA", "Alice One")
  Deliver("PART\t1234abcd\t2\tBBBB", "Alice One")
  EQ(Subs.Get("anything"), nil, "parts before accepting do nothing")
  StaticPopupDialogs.BLACKBOOK_TRANSFER_OFFER.OnAccept()
  Advance(0.5)
  Take()
  Deliver("PART\t1234abcd\t1\tAAAA", "Mallory Seven")
  Deliver("PART\twrongone\t1\tAAAA", "Alice One")
  Deliver("PART\t1234abcd\t0\tAAAA", "Alice One")
  Deliver("PART\t1234abcd\t3\tAAAA", "Alice One")
  Deliver("PART\t1234abcd\t1.5\tAAAA", "Alice One")
  Deliver("PART\t1234abcd\t1\t" .. string.rep("A", Const.Limits.transferChunk + 1), "Alice One")
  Deliver("PART\t1234abcd\t1\t", "Alice One")
  Deliver("PART\t1234abcd\t1\tAA\tAA", "Alice One")
  Deliver("PART\t1234abcd\t1", "Alice One")
  Deliver("PART\t1234abcd\t1\tAAAA", "Alice One")
  Deliver("PART\t1234abcd\t1\tCCCC", "Alice One") -- duplicate index
  Deliver("PART\t1234abcd\t2\tnot a code", "Alice One") -- completes: the content is checked
  OK(Printed("could not be used"), "a transfer that completes with garbage is reported")
  OK(Printed(L.ERR_CODE_FORMAT), "with the reason")
  Deliver("PART\t1234abcd\t1\tAAAA", "Alice One")
  EQ(#Take(), 0, "the finished session accepts nothing more")

  -- Parts arrive out of order and one is repeated with different content: the
  -- repeat is ignored, so the list only completes with all three real parts.
  Fresh()
  Me("Bob", "Two")
  local dupCode = ns.Codec.Encode({ id = "d00d00d00d01", name = "Dup test", author = "Alice One",
    exported = 1, records = {
      { name = "Dup One", verdict = "warn", labels = { spam = true }, comment = "c" },
      { name = "Dup Two", labels = { scam = true }, comment = "d" } } })
  local third = math.ceil(#dupCode / 3)
  local pieces = { dupCode:sub(1, third), dupCode:sub(third + 1, 2 * third), dupCode:sub(2 * third + 1) }
  Deliver(Offer("deadbeef", 3, 2, "Dup test"), "Alice One")
  StaticPopupDialogs.BLACKBOOK_TRANSFER_OFFER.OnAccept()
  Advance(0.5)
  Take()
  Deliver("PART	deadbeef	1	" .. pieces[1], "Alice One")
  Deliver("PART	deadbeef	1	GARBAGE", "Alice One")
  Deliver("PART	deadbeef	3	" .. pieces[3], "Alice One")
  EQ(Subs.Get("d00d00d00d01"), nil, "two distinct parts out of three do not complete the list")
  Deliver("PART	deadbeef	2	" .. pieces[2], "Alice One")
  local dupList = Subs.Get("d00d00d00d01")
  OK(dupList ~= nil and dupList.count == 2, "the third distinct part completes it, with the first part's real content")

  -- Declining through the popup.
  Fresh()
  Me("Bob", "Two")
  Deliver(Offer("abcdabcd", 2, 5, "Good"), "Alice One")
  StaticPopupDialogs.BLACKBOOK_TRANSFER_OFFER.OnCancel()
  Advance(0.5)
  local no = Take()
  EQ(#no, 1, "cancelling sends one message")
  EQ(no[1].text, "DECLINE\tabcdabcd", "a DECLINE")
  Deliver("PART\tabcdabcd\t1\tAAAA", "Alice One")
  StaticPopupDialogs.BLACKBOOK_TRANSFER_OFFER.OnCancel()
  Advance(0.5)
  EQ(#Take(), 0, "a second cancel does nothing")

  -- The popup's own timeout and a receiving session that never completes.
  Fresh()
  Me("Bob", "Two")
  Deliver(Offer("11112222", 2, 5, "Good"), "Alice One")
  Advance(57)
  local lapsed = Take()
  EQ(#lapsed, 1, "a popup left alone is declined")
  EQ(lapsed[1].text, "DECLINE\t11112222", "with a DECLINE")
  OK(hidden >= 1, "and hidden")
  Deliver(Offer("33334444", 2, 5, "Good"), "Alice One")
  StaticPopupDialogs.BLACKBOOK_TRANSFER_OFFER.OnAccept()
  Advance(0.5)
  Take()
  Deliver("PART\t33334444\t1\tAAAA", "Alice One")
  Advance(299)
  OK(not Printed("did not arrive"), "a session is still open after 299 seconds")
  Advance(2)
  OK(Printed("The list from Alice One did not arrive in time"), "a session expires after 5 minutes")
  Deliver("PART\t33334444\t2\tBBBB", "Alice One")
  EQ(#Take(), 0, "an expired session accepts nothing")
  Deliver(Offer("55556666", 2, 5, "Again"), "Alice One")
  EQ(shown, 3, "after expiry a new offer is welcome")

  -- Without a popup system an offer is declined with a notice.
  Fresh()
  Me("Bob", "Two")
  StaticPopupDialogs, StaticPopup_Show = nil, nil
  Deliver(Offer("aaaabbbb", 2, 5, "Good"), "Alice One")
  Advance(0.5)
  local noPopup = Take()
  EQ(#noPopup, 1, "no popup: one reply")
  EQ(noPopup[1].text, "DECLINE\taaaabbbb", "a DECLINE")
  OK(Printed(L.TRANSFER_NO_POPUP), "and the player is told why")
  StaticPopupDialogs, StaticPopup_Show = {}, function() shown = shown + 1 end

  -- Registration needs the addon message API.
  Fresh()
  C_ChatInfo = nil
  EQ(Transfer.Register(), false, "no addon message API: registration reports it")
  OK(Printed(L.MSG_NO_TRANSFER), "with a notice")
  StaticPopupDialogs, StaticPopup_Show, StaticPopup_Hide = nil, nil, nil
  UnitName = nil
end)

-- --- Summary -------------------------------------------------------------------

io.write(string.format("%d checks, %d failure(s)\n", checks, failures))
io.stdout:flush()
if failures > 0 then os.exit(1) end
os.exit(0)
