-- Nullgate's Blacklist: pure-module tests (DESIGN.md section 11).
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
  local path = root .. "/NullgatesBlacklist-Forever/" .. relative
  local chunk = assert(loadfile(path), "cannot load " .. path)
  chunk("NullgatesBlacklist-Forever", ns)
end

Load("Locale/Locale.lua")
Load("Locale/enUS.lua")
Load("Locale/deDE.lua")
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
Load("Community/Hash.lua")
Load("Community/Report.lua")
Load("Community/Aggregate.lua")
Load("Community/Consent.lua")
Load("Community/Rules.lua")
Load("Community/Roster.lua")
Load("Community/Envelope.lua")
Load("Community/Global.lua")
Load("Community/Net.lua")
Load("UI/ReportCard.lua")
Load("Enforce/Reply.lua")
Load("UI/ReplyControl.lua")
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
  NullgatesBlacklistDB = nil
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
  local chunk = assert(loadfile(root .. "/NullgatesBlacklist-Forever/Core/Settings.lua"))
  chunk("NullgatesBlacklist-Forever", ns)
  NullgatesBlacklistDB = nil
  local ok, db = pcall(ns.Settings.Init)
  math.randomseed = saved
  OK(ok, "Init works when math.randomseed is missing")
  OK(ok and type(db.settings.export.id) == "string" and #db.settings.export.id == 12, "export id still generated")
  ns.Settings, ns.db = savedSettings, savedDb
end)

Group("Settings migration", function()
  local Settings = ns.Settings
  NullgatesBlacklistDB = {
    version = 1,
    records = { ["a b"] = { name = "A B" } },
    settings = { language = "de" },
  }
  local db = Settings.Init()
  EQ(db.version, 1, "version stays 1")
  EQ(db.settings.language, "de", "existing value kept")
  EQ(db.settings.autoDecline, true, "missing value filled")
  EQ(db.records["a b"].name, "A B", "existing record kept")

  NullgatesBlacklistDB = { records = {} }
  db = Settings.Init()
  EQ(db.version, 1, "unversioned data migrated")
  EQ(type(db.community and db.community.reports), "table", "community tables created by migration")

  NullgatesBlacklistDB = { version = 99, settings = { language = "de" } }
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
  NullgatesBlacklistDB = nil
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
  NullgatesBlacklistDB = nil
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
  NullgatesBlacklistDB = nil
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
  EQ(ButtonTexts(root), L.CTX_IGNORE .. "|" .. L.CTX_WARN .. "|" .. L.CTX_CARD, "new player: ignore, warn and the report card")

  root = StubRoot()
  EQ(ContextMenu.Build(root, { name = "Chat Guy-Realm" }), true, "a chat name gets entries")
  EQ(ButtonTexts(root), L.CTX_IGNORE .. "|" .. L.CTX_WARN .. "|" .. L.CTX_CARD, "name context works like a unit")

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
  EQ(ButtonTexts(root), L.CTX_EDIT .. "|" .. L.CTX_REMOVE .. "|" .. L.CTX_CARD, "known player: edit, remove and the report card")
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
  EQ(ButtonTexts(root), L.CTX_IGNORE .. "|" .. L.CTX_WARN .. "|" .. L.CTX_ADOPT .. "|" .. L.CTX_CARD, "list-only player: adopt is offered")
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
  local chunk = assert(loadfile(root .. "/NullgatesBlacklist-Forever/UI/ContextMenu.lua"))
  local saved = ns.ContextMenu
  chunk("NullgatesBlacklist-Forever", ns)
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
  local overlay = created.NullgateBlacklistTargetMark
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
  local chunk = assert(loadfile(root .. "/NullgatesBlacklist-Forever/" .. path))
  chunk("NullgatesBlacklist-Forever", ns)
end

Group("Tooltip lines", function()
  local Tooltip, L = ns.Tooltip, ns.L
  local db = FreshDb()
  EQ(Tooltip.Lines("Nobody Here"), nil, "no lines without a verdict")

  ns.Records.Save("Tip Target", "ignore", { harassment = true, scam = true }, 'He said "hi" | bye')
  local lines = Tooltip.Lines("Tip Target")
  EQ(#lines, 3, "header, labels, comment")
  OK(lines[1].text:find("Nullgate's Blacklist: ", 1, true) and lines[1].text:find(L.VERDICT_IGNORE, 1, true), "header names the verdict")
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

-- --- Community: Hash (section 8.2) -----------------------------------------------------------

Group("Hash", function()
  local Hash = ns.Hash
  -- Published FNV-1a 32-bit test vectors.
  EQ(string.format("%08x", Hash.Fnv32("", 2166136261)), "811c9dc5", "fnv-1a of nothing is the offset basis")
  EQ(string.format("%08x", Hash.Fnv32("a", 2166136261)), "e40c292c", "fnv-1a of 'a'")
  EQ(string.format("%08x", Hash.Fnv32("foobar", 2166136261)), "bf9cf968", "fnv-1a of 'foobar'")

  local hash = Hash.Target("some player", 100)
  OK(hash:match("^%x+$") ~= nil and #hash == 16 and hash == hash:lower(), "a target hash is 16 lowercase hex digits")
  EQ(Hash.Target("some player", 100), hash, "the hash is deterministic")
  OK(Hash.Target("some player", 101) ~= hash, "another season gives another hash")
  OK(Hash.Target("other player", 100) ~= hash, "another player gives another hash")
  OK(hash:sub(1, 8) ~= hash:sub(9, 16), "the two halves are independent hashes")

  local secret = "0123456789abcdef0123456789abcdef"
  local token = Hash.Token(secret, hash)
  OK(token:match("^%x%x%x%x%x%x%x%x$") ~= nil, "a token is 8 hex digits")
  EQ(Hash.Token(secret, hash), token, "a token is stable for one install and target")
  OK(Hash.Token(secret, Hash.Target("other player", 100)) ~= token, "tokens differ per target")
  OK(Hash.Token("fedcba9876543210fedcba9876543210", hash) ~= token, "tokens differ per install")

  EQ(Hash.Day(86400 * 5 + 10), 5, "a day number")
  EQ(Hash.Day(86400 * 5 - 1), 4, "the day before midnight")
  EQ(Hash.Season(90 * 86400 * 3 + 5), 3, "a season number")
  EQ(Hash.Season(90 * 86400 * 3 - 1), 2, "the last second of a season")
  local candidates = Hash.Candidates("some player", 90 * 86400 * 4 + 1)
  EQ(candidates[1], Hash.Target("some player", 4), "the current season is tried first")
  EQ(candidates[2], Hash.Target("some player", 3), "and the previous one")
  EQ(Hash.ServerTime(), 1700000000, "without a server time call the local clock is used")
  GetServerTime = function() return 42 end
  EQ(Hash.ServerTime(), 42, "the server time call is preferred")
  GetServerTime = nil
end)

-- --- Community: Aggregate and tiers (sections 8.3, 8.4) ---------------------------------------

local TODAY = 20000
local function HashOf(n) return string.format("%08x%08x", n, n * 7 + 1) end
local function TokenOf(n) return string.format("%08x", n) end

-- Files `count` distinct reporters for a target and label at the given day.
local function Reports(hashValue, labelMask, count, day, source, firstToken)
  for index = 1, count do
    ns.Aggregate.Add(hashValue, labelMask, day, TokenOf((firstToken or 0) + index), source or "guild")
  end
  ns.Events:Fire("COMMUNITY_CHANGED") -- the resolver caches, so tell it the data changed
end

Group("Aggregate", function()
  local Aggregate, Const = ns.Aggregate, ns.Const
  local db = FreshDb()
  local H = HashOf(1)
  local SCAM, SPAM = Const.LabelValue.scam, Const.LabelValue.spam

  EQ(Aggregate.Add(H, SCAM + SPAM, TODAY, TokenOf(1), "guild"), 2, "one report with two labels adds two entries")
  EQ(Aggregate.Add(H, SCAM, TODAY - 5, TokenOf(1), "guild"), 0, "the same token again adds nothing")
  EQ(db.community.reports.guild[H].scam[TokenOf(1)], TODAY, "the first-seen day wins")
  OK(db.community.reports.guild[H].spam ~= nil, "both labels are stored")
  EQ(Aggregate.Add(H, SCAM, TODAY, TokenOf(1), "friends"), 1, "the same token in another source is separate")
  EQ(db.community.reports.friends[H].scam[TokenOf(1)], TODAY, "and stored under that source")

  -- Input is validated again here, even though the network layer checks it.
  EQ(Aggregate.Add("ABCDEF0123456789", SCAM, TODAY, TokenOf(2), "guild"), 0, "an upper-case hash is refused")
  EQ(Aggregate.Add("abc", SCAM, TODAY, TokenOf(2), "guild"), 0, "a short hash is refused")
  EQ(Aggregate.Add(H, SCAM, TODAY, "XYZ12345", "guild"), 0, "a non-hex token is refused")
  EQ(Aggregate.Add(H, SCAM, TODAY, TokenOf(2), "nowhere"), 0, "an unknown source is refused")
  EQ(Aggregate.Add(H, 0, TODAY, TokenOf(2), "guild"), 0, "mask 0 is refused")
  EQ(Aggregate.Add(H, 512, TODAY, TokenOf(2), "guild"), 0, "mask 512 is refused")
  EQ(Aggregate.Add(H, 1.5, TODAY, TokenOf(2), "guild"), 0, "a fractional mask is refused")
  EQ(Aggregate.Add(H, SCAM, "today", TokenOf(2), "guild"), 0, "a non-numeric day is refused")

  -- Tier boundaries for friends and guild: 3/90, 7/30, 10/7, 15/1.
  local function TierOf(count, day, extra)
    FreshDb()
    local target = HashOf(2)
    Reports(target, SCAM, count, day)
    return (Aggregate.Tier(target, "scam", { "guild" }, TODAY))
  end
  EQ(TierOf(2, TODAY), 0, "two reporters are no flag")
  EQ(TierOf(3, TODAY), 1, "three reporters in 90 days: tier 1")
  EQ(TierOf(3, TODAY - 89), 1, "a report from day 89 still counts")
  EQ(TierOf(3, TODAY - 90), 0, "a report from day 90 no longer counts")
  EQ(TierOf(6, TODAY - 20), 1, "six in 30 days stay tier 1")
  EQ(TierOf(7, TODAY - 20), 2, "seven in 30 days: tier 2")
  EQ(TierOf(7, TODAY - 29), 2, "day 29 is inside the 30 day window")
  EQ(TierOf(7, TODAY - 30), 1, "day 30 is outside it")
  EQ(TierOf(9, TODAY - 3), 2, "nine in 7 days are still tier 2")
  EQ(TierOf(10, TODAY - 3), 3, "ten in 7 days: tier 3")
  EQ(TierOf(10, TODAY - 6), 3, "day 6 is inside the 7 day window")
  EQ(TierOf(10, TODAY - 7), 2, "day 7 is outside it")
  EQ(TierOf(14, TODAY), 3, "fourteen today are tier 3")
  EQ(TierOf(15, TODAY), 4, "fifteen today: tier 4")
  EQ(TierOf(15, TODAY - 1), 3, "fifteen yesterday are not tier 4")

  -- Reporters are counted once across friends and guild, and the groups stay apart.
  FreshDb()
  local T = HashOf(3)
  Reports(T, SCAM, 2, TODAY, "guild", 0)         -- tokens 1,2
  Reports(T, SCAM, 2, TODAY, "friends", 1)       -- tokens 2,3: token 2 is the same reporter
  EQ((Aggregate.Tier(T, "scam", { "guild" }, TODAY)), 0, "two guild reporters alone are no flag")
  EQ((Aggregate.Tier(T, "scam", { "friends" }, TODAY)), 0, "two friend reporters alone are no flag")
  local tier, count = Aggregate.Tier(T, "scam", { "guild", "friends" }, TODAY)
  EQ(count, 3, "a reporter who told both sources counts once")
  EQ(tier, 1, "so three distinct reporters make a flag")
  EQ((Aggregate.Tier(T, "scam", { "global" }, TODAY)), 0, "nothing in global")
  Reports(T, SCAM, 5, TODAY, "global", 100)
  EQ((Aggregate.Tier(T, "scam", { "global" }, TODAY)), 1, "five global reporters: global tier 1")
  EQ((Aggregate.Tier(T, "scam", { "guild", "global" }, TODAY)), 0, "friends/guild and global are never combined")
  Reports(T, SCAM, 4, TODAY, "global", 200)
  EQ((Aggregate.Tier(T, "scam", { "global" }, TODAY)), 1, "nine global reporters are still below the global tier 2")
  EQ((Aggregate.Tier(T, "scam", { "guild" }, TODAY)), 0, "global reports never count for the guild")
  EQ((Aggregate.Tier(T, "scam", {}, TODAY)), 0, "no sources: no tier")

  -- Summary.
  FreshDb()
  local S = HashOf(4)
  EQ(Aggregate.Summary(S, { "guild" }, TODAY), nil, "nothing known: no summary")
  Reports(S, SCAM, 3, TODAY, "guild", 0)
  Reports(S, SPAM, 3, TODAY, "guild", 1) -- tokens 2..4: overlaps with the scam reporters
  local summary = Aggregate.Summary(S, { "guild" }, TODAY)
  EQ(summary.tier, 1, "the summary's tier is the best label tier")
  EQ(summary.count, 4, "reporters are counted once across labels")
  OK(summary.labels.scam and summary.labels.spam, "both labels reached a tier")
  Reports(HashOf(5), SCAM, 2, TODAY, "guild", 0)
  EQ(Aggregate.Summary(HashOf(5), { "guild" }, TODAY), nil, "a target below tier 1 has no summary")

  -- Retraction is per source.
  FreshDb()
  local R = HashOf(6)
  Aggregate.Add(R, SCAM + SPAM, TODAY, TokenOf(1), "guild")
  Aggregate.Add(R, SCAM, TODAY, TokenOf(1), "friends")
  EQ(Aggregate.Retract(R, TokenOf(9), "guild"), false, "an unknown token retracts nothing")
  EQ(Aggregate.Retract(R, TokenOf(1), "guild"), true, "a token is retracted")
  EQ(ns.db.community.reports.guild[R], nil, "the empty target is dropped")
  OK(ns.db.community.reports.friends[R] ~= nil, "the other source keeps its report")
  EQ(Aggregate.Retract(R, TokenOf(1), "guild"), false, "retracting twice does nothing")

  -- Expiry and the counters.
  FreshDb()
  Aggregate.Add(HashOf(7), SCAM, TODAY - 100, TokenOf(1), "guild")
  Aggregate.Add(HashOf(7), SCAM, TODAY - 90, TokenOf(2), "guild")
  Aggregate.Add(HashOf(7), SCAM, TODAY - 91, TokenOf(3), "guild")
  Aggregate.Add(HashOf(8), SCAM, TODAY - 200, TokenOf(1), "friends")
  Aggregate.Expire(TODAY)
  local tokens, targets = Aggregate.Counts()
  EQ(tokens, 1, "only the report from day 90 is kept")
  EQ(targets, 1, "the target with only old reports is gone")
  EQ(ns.db.community.reports.friends[HashOf(8)], nil, "its table is gone as well")

  -- Caps.
  FreshDb()
  local C = HashOf(9)
  for index = 1, 55 do Aggregate.Add(C, SCAM, TODAY - 60 + index, TokenOf(index), "guild") end
  local kept = 0
  for _ in pairs(ns.db.community.reports.guild[C].scam) do kept = kept + 1 end
  EQ(kept, 50, "at most 50 tokens per target and label")
  EQ(ns.db.community.reports.guild[C].scam[TokenOf(1)], nil, "the oldest are dropped first")
  OK(ns.db.community.reports.guild[C].scam[TokenOf(55)] ~= nil, "the newest is kept")
  local old = Const.Community.targetCap
  Const.Community.targetCap = 3
  FreshDb()
  for index = 1, 5 do Aggregate.Add(HashOf(100 + index), SCAM, TODAY, TokenOf(1), "guild") end
  local _, targetCount = Aggregate.Counts()
  EQ(targetCount, 3, "no new targets above the cap")
  EQ(Aggregate.Add(HashOf(100 + 1), SCAM, TODAY, TokenOf(2), "guild"), 1, "an existing target still takes reports")
  Aggregate.Add(HashOf(200), SCAM, TODAY, TokenOf(1), "friends")
  local _, friendTargets = Aggregate.Counts()
  EQ(friendTargets, 4, "the cap is per source")
  Const.Community.targetCap = old

  local oldTotal = Const.Community.totalCap
  Const.Community.totalCap = 40
  FreshDb()
  for index = 1, 60 do Aggregate.Add(HashOf(300 + index), SCAM, TODAY - 100 + index, TokenOf(1), "guild") end
  local total = Aggregate.Counts()
  OK(total <= 40, "the whole store stays under its cap (" .. total .. ")")
  EQ(ns.db.community.reports.guild[HashOf(300 + 1)], nil, "the oldest reports are dropped first when it is full")
  OK(ns.db.community.reports.guild[HashOf(300 + 60)] ~= nil, "the newest survive")
  Const.Community.totalCap = oldTotal

  -- Counters always match a recount.
  FreshDb()
  for index = 1, 30 do Aggregate.Add(HashOf(400 + index % 7), SCAM + SPAM, TODAY - index, TokenOf(index), index % 2 == 0 and "guild" or "friends") end
  Aggregate.Retract(HashOf(400 + 3), TokenOf(3), "friends")
  Aggregate.Expire(TODAY + 80)
  local counted = 0
  for _, byHash in pairs(ns.db.community.reports) do
    for _, byLabel in pairs(byHash) do
      for _, byToken in pairs(byLabel) do for _ in pairs(byToken) do counted = counted + 1 end end
    end
  end
  EQ(Aggregate.Counts(), counted, "the counter equals a recount")
  Aggregate.Purge()
  local after, afterTargets = Aggregate.Counts()
  EQ(after + afterTargets, 0, "purge empties the store")
end)

-- --- Community: Report and the wire format (sections 8.6, 8.7) --------------------------------

Group("Reporters and the report card", function()
  local Aggregate, Rules, Consent, Hash, Const = ns.Aggregate, ns.Rules, ns.Consent, ns.Hash, ns.Const
  local SCAM, SPAM = Const.LabelValue.scam, Const.LabelValue.spam

  -- Global hashes use their own salt.
  OK(Hash.Target("some player", 100, "global") ~= Hash.Target("some player", 100), "a global hash differs from the friends and guild hash")
  EQ(Hash.Target("some player", 100, "friends"), Hash.Target("some player", 100), "friends and guild share one hash")
  EQ(#Hash.AllCandidates("some player", 1700000000), 4, "all candidates cover both groups and two seasons")

  -- The sending character is kept for friends and guild, never for global.
  local db = FreshDb()
  local H = HashOf(40)
  Aggregate.Add(H, SCAM + SPAM, TODAY, TokenOf(1), "guild", "Bob-Realm")
  Aggregate.Add(H, SCAM, TODAY - 3, TokenOf(2), "friends", "Carol-Realm")
  Aggregate.Add(H, SCAM, TODAY, TokenOf(3), "global", "Dave-Realm")
  EQ(db.community.reporters.guild[H][TokenOf(1)], "Bob-Realm", "a guild reporter is kept")
  EQ(db.community.reporters.friends[H][TokenOf(2)], "Carol-Realm", "a friend reporter is kept")
  EQ(db.community.reporters.global, nil, "a global reporter is never stored")

  local detail = Aggregate.Detail({ H }, "guild", TODAY)
  EQ(detail.count, 1, "the guild detail counts one reporter")
  EQ(detail.labels.scam, 1, "per label")
  EQ(detail.reporters[1].name, "Bob-Realm", "and names the reporter")
  OK(detail.reporters[1].labels.scam and detail.reporters[1].labels.spam, "with the labels they reported")
  local global = Aggregate.Detail({ H }, "global", TODAY)
  EQ(global.count, 1, "the global detail only counts")
  EQ(global.reporters, nil, "and has no reporter list")
  EQ(Aggregate.Detail({ HashOf(41) }, "guild", TODAY), nil, "nothing held gives no detail")

  -- Reporters go away with their reports.
  Aggregate.Retract(H, TokenOf(1), "guild")
  EQ(db.community.reporters.guild[H], nil, "a retraction forgets the reporter")
  Aggregate.Add(HashOf(42), SCAM, TODAY - 200, TokenOf(5), "friends", "Old-Realm")
  Aggregate.Expire(TODAY)
  EQ(db.community.reporters.friends[HashOf(42)], nil, "expiry forgets the reporter")
  OK(db.community.reporters.friends[H] ~= nil, "a reporter still inside the window stays")
  Aggregate.Purge()
  EQ(next(ns.db.community.reporters), nil, "purging forgets every reporter")

  -- The card: what every receiving source holds, even below tier 1.
  FreshDb()
  UnitName = function(unit) if unit == "player" then return "Alice", "One" end end
  local now = Hash.ServerTime()
  local today = Hash.Day(now)
  local key = "card target"
  EQ(#Rules.Card("Card Target").sources, 0, "no consent: an empty card")
  EQ(Rules.Card("Card Target").receiving, false, "and it says nothing is received")
  Consent.ConfirmGlobal()
  Consent.SetToggle("guild", "receive", true)
  Consent.SetToggle("global", "receive", true)
  local guildHash = Hash.Candidates(key, now, "friends")[1]
  local globalHash = Hash.Candidates(key, now, "global")[1]
  Aggregate.Add(guildHash, SCAM, today, TokenOf(1), "guild", "Bob-Realm")
  for n = 1, 6 do Aggregate.Add(globalHash, SCAM, today, TokenOf(10 + n), "global") end
  Aggregate.Add(globalHash, SCAM, today, TokenOf(30), "guild", "Wrong-Realm") -- a guild report under the global hash
  local card = Rules.Card("Card Target")
  EQ(card.receiving, true, "receiving is on")
  EQ(#card.sources, 2, "guild and global both show")
  local bySource = {}
  for _, entry in ipairs(card.sources) do bySource[entry.source] = entry end
  EQ(bySource.guild.count, 1, "one guild reporter")
  EQ(bySource.guild.tier, 0, "below tier 1 still shows, at tier 0")
  EQ(bySource.guild.reporters[1].name, "Bob-Realm", "the guild card names its reporter")
  EQ(bySource.global.count, 6, "six global reporters")
  EQ(bySource.global.tier, 1, "which reach tier 1")
  EQ(bySource.global.reporters, nil, "global never names reporters")
  -- The card's text: guild names its reporter, global only counts.
  local function CardText(name)
    local parts = {}
    for _, line in ipairs(ns.ReportCard.Lines(name)) do parts[#parts + 1] = line.text end
    return table.concat(parts, "\n")
  end
  local text = CardText("Card Target")
  OK(text:find(ns.L.CARD_OWN_NONE, 1, true), "the card says the player is not on your list")
  OK(text:find("Bob", 1, true), "the guild block names its reporter")
  OK(not text:find("Wrong", 1, true), "a report filed under the other group's hash is not shown")
  OK(text:find(ns.L.CARD_ANONYMOUS, 1, true), "the global block says it is anonymous")
  OK(text:find(ns.L.CARD_BELOW_TIER, 1, true), "a source below the first tier says so")
  ns.Records.Save("Card Target", "warn", { spam = true }, "mine")
  OK(CardText("Card Target"):find("mine", 1, true), "an own record shows with its comment")

  Rules.Hide("Card Target")
  EQ(Rules.Card("Card Target").hidden, true, "a hidden flag says so on the card")
  OK(CardText("Card Target"):find(ns.L.CARD_HIDDEN, 1, true), "and in its text")
  FreshDb()
  OK(CardText("Card Target"):find(ns.L.CARD_OFF, 1, true), "without consent the card says receiving is off")
end)

Group("Report", function()
  local Report, Hash, Const = ns.Report, ns.Hash, ns.Const
  local now = 1700000000
  local today = Hash.Day(now)
  local secret = "0123456789abcdef0123456789abcdef"
  local share = { scam = true, spam = true, toxicity = true }
  local function Rec(name, verdict, labels, created)
    return { name = name, verdict = verdict, labels = labels, created = created, comment = "private comment" }
  end

  local items = Report.Build({
    Rec("Scam Guy", "ignore", { scam = true, other = true }, now - 3 * 86400),
    Rec("Warned Guy", "warn", { scam = true }, now),
    Rec("Private Guy", "ignore", { private_dispute = true, other = true }, now),
    Rec("Old Guy", "ignore", { spam = true }, now - 400 * 86400),
    Rec("Future Guy", "ignore", { toxicity = true }, now + 30 * 86400),
    Rec("Fresh Guy", "ignore", { scam = true, spam = true }, nil),
  }, { shareLabels = share, secret = secret, now = now })
  EQ(#items, 4, "only ignore records with a shareable label are reported")
  local byKey = {}
  for _, item in ipairs(items) do byKey[item.key] = item end
  EQ(byKey["warned guy"], nil, "a warn record is not reported")
  EQ(byKey["private guy"], nil, "a record with only private labels is not reported")
  EQ(byKey["scam guy"].mask, Const.LabelValue.scam, "labels that are not shared are left out of the mask")
  EQ(byKey["scam guy"].day, today - 3, "the record's day is used")
  EQ(byKey["old guy"].day, today - 89, "an old record is clamped to the window")
  EQ(byKey["future guy"].day, today, "a day in the future is clamped to today")
  EQ(byKey["fresh guy"].day, today, "a record without a date counts as today")
  EQ(byKey["scam guy"].hash, Hash.Target("scam guy", Hash.Season(now)), "the hash is of the lower-case key")
  EQ(byKey["scam guy"].token, Hash.Token(secret, byKey["scam guy"].hash), "the token follows from secret and hash")
  for index = 2, #items do OK(items[index - 1].hash <= items[index].hash, "items are sorted by hash") end
  for _, item in ipairs(items) do
    OK(not (item.hash .. item.token):find("[^0-9a-f]"), "an item carries nothing but hex")
  end

  -- Messages: six to a message, never above 255 bytes, and no names or comments.
  local many = {}
  for index = 1, 14 do
    many[index] = { key = "p" .. index, hash = HashOf(index), mask = 511, day = today, token = TokenOf(index) }
  end
  local messages = Report.Messages(many)
  EQ(#messages, 3, "fourteen items make three messages")
  for _, message in ipairs(messages) do OK(#message <= 255, "a report message fits an addon message (" .. #message .. ")") end
  OK(messages[1]:sub(1, 3) == "R1\t", "a report message starts with R1 and a TAB")
  EQ(#Report.Parse(messages[1], today).items, 6, "six records in the first message")
  EQ(#Report.Parse(messages[3], today).items, 2, "two in the last")
  local joined = table.concat(Report.Messages(items), "\n")
  OK(not joined:find("Guy") and not joined:find("private") and not joined:find("scam"), "no name, comment or label text is sent")
  local retract = Report.RetractMessages({ { hash = HashOf(1), token = TokenOf(1) }, { hash = HashOf(2), token = TokenOf(2) } })
  EQ(#retract, 1, "two retractions fit one message")
  EQ(retract[1], "X1\t" .. HashOf(1) .. ":" .. TokenOf(1) .. ";" .. HashOf(2) .. ":" .. TokenOf(2), "retraction layout")
  local back = Report.Parse(retract[1], today)
  EQ(back.kind, "X1", "a retraction parses")
  EQ(back.items[2].hash, HashOf(2), "with its items")

  -- Parsing is strict.
  local good = HashOf(1) .. ":3:" .. today .. ":" .. TokenOf(1)
  local function Parse(text) return Report.Parse(text, today) end
  EQ(Parse("R1\t" .. good).items[1].mask, 3, "a good record parses")
  EQ(Parse(nil), nil, "not a string")
  EQ(Parse("R1\t" .. string.rep(good .. ";", 10)), nil, "a message above 255 bytes is dropped")
  EQ(Parse("R1" .. good), nil, "the TAB is required")
  EQ(Parse("R1\t"), nil, "an empty body")
  EQ(Parse("R9\t" .. good), nil, "an unknown message word")
  EQ(Parse("zz"), nil, "garbage")
  EQ(Parse("H1").kind, "H1", "a hello")
  EQ(Parse("H2").kind, "H2", "a hello reply")
  EQ(Parse("H1 extra"), nil, "a hello with trailing text is dropped")
  EQ(#Parse("R1\t" .. string.upper(HashOf(10)) .. ":3:" .. today .. ":" .. TokenOf(1)).items, 0, "an upper-case hash is dropped")
  EQ(#Parse("R1\t" .. "abcd:3:" .. today .. ":" .. TokenOf(1)).items, 0, "a short hash is dropped")
  EQ(#Parse("R1\t" .. HashOf(1) .. ":3:" .. today .. ":abcd").items, 0, "a short token is dropped")
  EQ(#Parse("R1\t" .. HashOf(1) .. ":0:" .. today .. ":" .. TokenOf(1)).items, 0, "mask 0 is dropped")
  EQ(#Parse("R1\t" .. HashOf(1) .. ":512:" .. today .. ":" .. TokenOf(1)).items, 0, "mask 512 has no known bit left")
  EQ(Parse("R1\t" .. HashOf(1) .. ":513:" .. today .. ":" .. TokenOf(1)).items[1].mask, 1, "unknown mask bits are clamped away")
  EQ(#Parse("R1\t" .. HashOf(1) .. ":1234:" .. today .. ":" .. TokenOf(1)).items, 0, "a four digit mask is dropped")
  EQ(#Parse("R1\t" .. HashOf(1) .. ":3:" .. (today + 1) .. ":" .. TokenOf(1)).items, 1, "tomorrow is accepted")
  EQ(#Parse("R1\t" .. HashOf(1) .. ":3:" .. (today + 2) .. ":" .. TokenOf(1)).items, 0, "two days ahead is dropped")
  EQ(#Parse("R1\t" .. HashOf(1) .. ":3:" .. (today - 90) .. ":" .. TokenOf(1)).items, 1, "day 90 is accepted")
  EQ(#Parse("R1\t" .. HashOf(1) .. ":3:" .. (today - 91) .. ":" .. TokenOf(1)).items, 0, "day 91 is dropped")
  EQ(#Parse("R1\t" .. HashOf(1) .. ":3:-5:" .. TokenOf(1)).items, 0, "a negative day is dropped")
  EQ(#Parse("R1\t" .. HashOf(1) .. ":3:x:" .. TokenOf(1)).items, 0, "a non-numeric day is dropped")
  local mixed = Parse("R1\t" .. good .. ";broken;" .. HashOf(2) .. ":1:" .. today .. ":" .. TokenOf(2))
  EQ(#mixed.items, 2, "a bad record does not spoil the good ones around it")
  local seven = {}
  for index = 1, 7 do seven[index] = HashOf(index) .. ":1:" .. today .. ":" .. TokenOf(index) end
  EQ(#Parse("R1\t" .. table.concat(seven, ";")).items, 6, "at most six records are read")
  EQ(#Parse("X1\t" .. HashOf(1) .. ":" .. TokenOf(1) .. ";bad").items, 1, "a bad retraction is dropped alone")
end)

-- --- Community: Consent (section 8.9) ----------------------------------------------------------

Group("Consent", function()
  local Consent, Settings, Const = ns.Consent, ns.Settings, ns.Const
  FreshDb()
  EQ(Consent.Active(), false, "nothing is confirmed at first")
  EQ(Consent.Allows("guild", "send"), false, "every switch is off")
  EQ(#Consent.Receiving() + #Consent.Sending(), 0, "no source is active")
  EQ(Consent.SetToggle("guild", "send", true), false, "a switch cannot be turned on before the disclosure is confirmed")
  EQ(Settings.Get("community.guild.send"), false, "and stays off")

  local changes = 0
  ns.Events:On("COMMUNITY_CHANGED", function() changes = changes + 1 end)
  Consent.Confirm()
  EQ(Consent.Active(), true, "confirming activates consent")
  EQ(changes, 1, "and announces it")
  EQ(Consent.Allows("guild", "send"), false, "confirming alone does not turn anything on")
  OK(Consent.SetToggle("guild", "send", true), "a switch can be turned on")
  OK(Consent.SetToggle("friends", "receive", true), "each source and direction is its own switch")
  EQ(Consent.Allows("guild", "send"), true, "guild send is on")
  EQ(Consent.Allows("guild", "receive"), false, "guild receive is still off")
  EQ(Consent.Allows("friends", "send"), false, "friends send is still off")
  EQ(table.concat(Consent.Sending(), ","), "guild", "the sending sources")
  EQ(table.concat(Consent.Receiving(), ","), "friends", "the receiving sources")
  EQ(Consent.SetToggle("global", "receive", true), false, "global is not available yet")
  EQ(Consent.Allows("global", "receive"), false, "and never allowed")
  EQ(Consent.SetToggle("guild", "bogus", true), false, "an unknown direction is refused")
  EQ(Consent.Allows("guild", "bogus"), false, "and never allowed")

  -- A new disclosure version switches everything off until confirmed again.
  Const.ConsentVersion = Const.ConsentVersion + 1
  EQ(Consent.Active(), false, "a new disclosure version needs a new confirmation")
  EQ(Consent.Allows("guild", "send"), false, "so the switches stop working")
  Consent.Confirm()
  EQ(Consent.Allows("guild", "send"), true, "and work again once confirmed")
  Const.ConsentVersion = Const.ConsentVersion - 1
  Settings.Set("community.consentVersion", Const.ConsentVersion)

  -- Revoke.
  Settings.Set("community.rules", { { label = "scam", source = "guild", minTier = 2, verdict = "warn" } })
  ns.Aggregate.Add(HashOf(1), 1, TODAY, TokenOf(1), "guild")
  ns.db.community.sent = { guild = { [HashOf(1)] = 1 } }
  Consent.Revoke()
  EQ(Consent.Active(), false, "revoking withdraws consent")
  EQ(Settings.Get("community.guild.send"), false, "and switches everything off")
  EQ(Settings.Get("community.friends.receive"), false, "in both directions")
  local tokens = ns.Aggregate.Counts()
  EQ(tokens, 0, "and deletes the received reports")
  EQ(next(ns.db.community.sent), nil, "and forgets what was announced")
  EQ(#Settings.Get("community.rules"), 1, "the player's rules stay")
end)

-- --- Community: Rules, hidden flags and the resolver (sections 8.5, 8.8, 6.3) -----------------

Group("Rules and the community verdict", function()
  local Rules, Consent, Aggregate, Hash, Resolver, Const = ns.Rules, ns.Consent, ns.Aggregate, ns.Hash, ns.Resolver, ns.Const
  FreshDb()
  UnitName = function(unit) if unit == "player" then return "Alice", "One" end end
  local now = Hash.ServerTime()
  local today = Hash.Day(now)
  local SCAM = Const.LabelValue.scam

  -- Rule checks.
  local function Rule(label, source, tier, verdict) return { label = label, source = source, minTier = tier, verdict = verdict } end
  EQ(Rules.Check(Rule("scam", "guild", 2, "warn")), nil, "a good rule")
  EQ(Rules.Check(Rule("nonsense", "guild", 2, "warn")), "ERR_RULE", "an unknown label")
  EQ(Rules.Check(Rule("scam", "mars", 2, "warn")), "ERR_RULE", "an unknown source")
  EQ(Rules.Check(Rule("scam", "any", 2, "warn")), "ERR_RULE", "there is no 'any' source: sources are never mixed")
  EQ(Rules.Check(Rule("scam", "guild", 2, "notice")), "ERR_RULE", "a rule raises to warn or ignore only")
  EQ(Rules.Check(Rule("scam", "guild", 5, "warn")), "ERR_RULE", "tier above 4")
  EQ(Rules.Check(Rule("scam", "guild", 0, "warn")), "ERR_RULE", "tier below 1")
  EQ(Rules.Check(Rule("scam", "guild", 1.5, "warn")), "ERR_RULE", "a fractional tier")
  EQ(Rules.Check(Rule("scam", "global", 2, "warn")), "ERR_RULE_GLOBAL", "a global rule needs tier 3")
  EQ(Rules.Check(Rule("scam", "global", 3, "warn")), nil, "a global rule at tier 3 is fine")
  EQ(Rules.Check("rule"), "ERR_RULE", "not a table")

  local ok, err = Rules.Add(Rule("scam", "guild", 2, "warn"))
  OK(ok, "a rule is added")
  OK(Rules.Add(Rule("scam", "guild", 2, "warn")), "the same rule again is accepted")
  EQ(#Rules.List(), 1, "but stored once")
  ok, err = Rules.Add(Rule("scam", "global", 1, "ignore"))
  EQ(ok, false, "an invalid rule is refused")
  EQ(err, "ERR_RULE_GLOBAL", "with the reason")
  OK(Rules.Add(Rule("spam", "friends", 1, "ignore")), "a second rule")
  OK(Rules.Remove(1), "a rule is removed")
  EQ(Rules.Remove(5), false, "a rule that is not there cannot be removed")
  EQ(#Rules.List(), 1, "one rule left")
  Rules.Remove(1)

  -- Nothing without consent.
  local key = "flagged one"
  local hash = Hash.Candidates(key, now)[1]
  Reports(hash, SCAM, 3, today, "guild", 0)
  EQ(Resolver.Verdict("Flagged One"), nil, "reports alone do nothing without consent")
  Consent.Confirm()
  EQ(Resolver.Verdict("Flagged One"), nil, "and nothing until receiving from that source is switched on")
  Consent.SetToggle("guild", "receive", true)
  EQ(Resolver.Verdict("Flagged One"), "notice", "a tier 1 flag is only a notice")
  local reasons = Resolver.Sources("Flagged One")
  EQ(#reasons, 1, "one reason")
  EQ(reasons[1].source, "community", "from the community")
  EQ(reasons[1].from, "guild", "naming the source")
  EQ(reasons[1].tier, 1, "with its tier")
  EQ(reasons[1].count, 3, "and the number of reporters")
  OK(reasons[1].labels.scam ~= nil, "and the labels")

  -- Rules raise the verdict, per source and per tier.
  Rules.Add(Rule("scam", "guild", 2, "warn"))
  EQ(Resolver.Verdict("Flagged One"), "notice", "a rule for tier 2 does not match a tier 1 flag")
  Reports(hash, SCAM, 4, today - 10, "guild", 10)  -- now 7 reporters within 30 days: tier 2
  EQ(Resolver.Verdict("Flagged One"), "warn", "the rule matches once the tier is reached")
  Rules.Add(Rule("scam", "guild", 2, "ignore"))
  EQ(Resolver.Verdict("Flagged One"), "ignore", "the strongest matching rule wins")
  Rules.Remove(2)
  Rules.Remove(1)
  Rules.Add(Rule("scam", "friends", 1, "ignore"))
  EQ(Resolver.Verdict("Flagged One"), "notice", "a rule for another source does not apply")
  Rules.Remove(1)
  Rules.Add(Rule("spam", "guild", 1, "ignore"))
  EQ(Resolver.Verdict("Flagged One"), "notice", "a rule for another label does not apply")
  Rules.Remove(1)

  -- Friends and guild are separate sources.
  local friendKey = "friendly flag"
  local friendHash = Hash.Candidates(friendKey, now)[1]
  Reports(friendHash, SCAM, 3, today, "friends", 0)
  EQ(Resolver.Verdict("Friendly Flag"), nil, "friend reports do not count while only the guild is received")
  Consent.SetToggle("friends", "receive", true)
  EQ(Resolver.Verdict("Friendly Flag"), "notice", "they count once that source is switched on")
  EQ(Resolver.Sources("Friendly Flag")[1].from, "friends", "and say where they came from")
  local split = "split flag"
  local splitHash = Hash.Candidates(split, now)[1]
  Reports(splitHash, SCAM, 2, today, "guild", 0)
  Reports(splitHash, SCAM, 2, today, "friends", 10)
  EQ(Resolver.Verdict("Split Flag"), nil, "two guild and two friend reporters do not add up to a flag")
  Reports(HashOf(77), SCAM, 20, today, "global", 0)
  local globalHash = Hash.Candidates("global flag", now)[1]
  Reports(globalHash, SCAM, 40, today, "global", 0)
  EQ(Resolver.Verdict("Global Flag"), nil, "global reports never affect a verdict here")

  -- The previous season's hash is found as well.
  local oldHash = Hash.Candidates("season flag", now)[2]
  Reports(oldHash, SCAM, 3, today, "guild", 0)
  EQ(Resolver.Verdict("Season Flag"), "notice", "reports filed under the previous season are found")

  -- Own record wins; the strongest of everything wins otherwise.
  ns.Records.Save("Flagged One", "warn", { spam = true }, "mine")
  EQ(Resolver.Verdict("Flagged One"), "warn", "an own record wins over community data")
  ns.Records.Remove("Flagged One")
  EQ(Resolver.Verdict("Flagged One"), "notice", "and community data is back when it is gone")
  ns.Subscriptions.Import({ id = "e1e1e1", name = "Listy", author = "Bob Two", records = {
    ["flagged one"] = { name = "Flagged One", labels = { scam = true }, comment = "c" } }, count = 1 })
  ns.Subscriptions.SetRule("e1e1e1", "scam", "ignore")
  EQ(Resolver.Verdict("Flagged One"), "ignore", "the strongest of lists and community wins")
  EQ(#Resolver.Sources("Flagged One"), 2, "with both reasons listed")
  ns.Subscriptions.Remove("e1e1e1")

  -- Tooltip lines name the source, the count and the tier.
  local lines = ns.Tooltip.Lines("Flagged One")
  local found
  for _, line in ipairs(lines) do
    if line.text:find("Guild", 1, true) and line.text:find("7 players", 1, true) then found = line.text end
  end
  OK(found ~= nil, "the tooltip names the source and the number of reporters")
  OK(found and found:find("Elevated", 1, true) ~= nil, "and the tier")

  -- "This flag is wrong".
  local hidden = Rules.Hide("Flagged One")
  OK(hidden, "a flag can be hidden")
  EQ(Resolver.Verdict("Flagged One"), nil, "hiding removes the community verdict")
  OK(Rules.IsHidden("Flagged One"), "it is reported as hidden")
  EQ(Rules.HiddenList()[1].name, "Flagged One", "the hidden list shows the name")
  EQ(#Rules.HiddenList(), 1, "once per player")
  OK(Rules.Unhide(Rules.HiddenList()[1].hash), "it can be undone")
  EQ(Resolver.Verdict("Flagged One"), "notice", "and the flag is back")
  EQ(Rules.Unhide("0000000000000000"), false, "unknown hashes cannot be unhidden")

  -- The context menu offers it only for a flag that comes from the community.
  local menuRoot = { items = {} }
  function menuRoot:CreateDivider() end
  function menuRoot:CreateTitle() end
  function menuRoot:CreateButton(text) self.items[#self.items + 1] = text end
  ns.ContextMenu.Build(menuRoot, { name = "Flagged One" })
  OK(table.concat(menuRoot.items, "|"):find(ns.L.CTX_WRONG, 1, true) ~= nil, "the menu offers 'this flag is wrong'")
  menuRoot = { items = {}, CreateDivider = menuRoot.CreateDivider, CreateTitle = menuRoot.CreateTitle, CreateButton = menuRoot.CreateButton }
  ns.ContextMenu.Build(menuRoot, { name = "Nobody Known" })
  OK(table.concat(menuRoot.items, "|"):find(ns.L.CTX_WRONG, 1, true) == nil, "but not for a player without a community flag")
  UnitName = nil
end)

-- --- Community: Roster ----------------------------------------------------------------------------

Group("Roster", function()
  local Roster = ns.Roster
  Roster.Reset()
  local list = {
    { name = "Alice One-Realm", connected = true },
    { name = "Bob Two", connected = false },
  }
  C_FriendList = {
    GetNumFriends = function() return #list end,
    GetFriendInfoByIndex = function(index) return list[index] end,
  }
  OK(Roster.IsFriend("alice one"), "a friend is found, ignoring case and the realm")
  OK(Roster.IsFriend("Bob Two"), "an offline friend is a friend too")
  EQ(Roster.IsFriend("Carol Three"), false, "a stranger is not")
  EQ(Roster.IsOnline("Alice One"), true, "an online friend")
  EQ(Roster.IsOnline("Bob Two"), false, "an offline friend")
  EQ(table.concat(Roster.OnlineNames(), ","), "Alice One", "the online names")
  EQ(Roster.IsFriend(nil), false, "no name, no friend")

  local arrivals = {}
  Roster.OnOnline(function(names) arrivals[#arrivals + 1] = table.concat(names, ",") end)
  Roster.Refresh()
  EQ(arrivals[1], "Alice One", "the first scan reports who is online")
  Roster.Refresh()
  EQ(#arrivals, 1, "a second scan reports nobody new")
  list[2].connected = true
  Roster.Refresh()
  EQ(arrivals[2], "Bob Two", "a friend who comes online is reported")
  list[1].connected = false
  Roster.Refresh()
  list[1].connected = true
  Roster.Refresh()
  EQ(arrivals[3], "Alice One", "and one who comes back")

  issecretvalue = function(value) return value == SECRET end
  list[#list + 1] = { name = SECRET, connected = true }
  Roster.Reset()
  EQ(Roster.IsFriend(SECRET), false, "a secret name is never a friend")
  issecretvalue = nil
  C_FriendList = { GetNumFriends = function() error("boom") end }
  Roster.Reset()
  EQ(Roster.IsFriend("Alice One"), false, "a failing client call gives an empty list")
  C_FriendList = nil
  Roster.Reset()
  EQ(Roster.IsFriend("Alice One"), false, "no friend list API gives an empty list")
  IsInGuild = nil
  EQ(Roster.InGuild(), false, "no guild API: not in a guild")
  IsInGuild = function() return true end
  EQ(Roster.InGuild(), true, "in a guild")
  IsInGuild = nil
end)

-- --- Community: Net, the background sending and receiving ----------------------------------------

Group("Net", function()
  local Net, Roster, Consent, Aggregate, Hash, Report, Const, Settings = ns.Net, ns.Roster, ns.Consent,
    ns.Aggregate, ns.Hash, ns.Report, ns.Const, ns.Settings
  local PREFIX = Const.COMMUNITY_PREFIX

  -- A scripted clock and a recording transport.
  local now, timers, sent = 0, {}, {}
  local sendOk = true
  Net.io = {
    send = function(prefix, text, channel, target)
      if not sendOk then return false end
      sent[#sent + 1] = { prefix = prefix, text = text, channel = channel, target = target, at = now }
      return true
    end,
    after = function(delay, fn) timers[#timers + 1] = { at = now + delay, fn = fn } end,
    now = function() return now end,
    serverTime = function() return 1700000000 end,
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
  local friendList = {}
  C_FriendList = {
    GetNumFriends = function() return #friendList end,
    GetFriendInfoByIndex = function(index) return friendList[index] end,
  }
  local inGuild = true
  IsInGuild = function() return inGuild end

  local today = Hash.Day(1700000000)
  local function Fresh()
    sendOk = true
    Advance(100000)
    Net.Reset()
    Roster.Reset()
    FreshDb()
    Me("Alice", "One")
    sent, printed, friendList, inGuild = {}, {}, {}, true
    Consent.Confirm()
  end
  local function Spy()
    local counter = { n = 0 }
    ns.Events:On("COMMUNITY_CHANGED", function() counter.n = counter.n + 1 end)
    return counter
  end
  local function Rec(name, verdict, labels, comment)
    return ns.Records.Save(name, verdict, labels, comment or "a private comment")
  end
  local function Parse(message) return Report.Parse(message.text, today) end
  local function HashFor(name) return Hash.Target(string.lower(name), Hash.Season(1700000000)) end

  -- Nothing is sent without consent.
  Fresh()
  ns.Settings.Set("community.consentVersion", 0)
  Rec("Bad One", "ignore", { scam = true })
  Net.Sync()
  EQ(#Take(), 0, "no consent: nothing is sent")
  Consent.Confirm()
  Net.Sync()
  EQ(#Take(), 0, "consent without a send switch: nothing is sent")

  -- Guild: the first report goes out, then only changes.
  Fresh()
  Consent.SetToggle("guild", "send", true)
  Rec("Bad One", "ignore", { scam = true, toxicity = true }, "very private comment")
  Rec("Warned Two", "warn", { scam = true })
  Rec("Dispute Three", "ignore", { private_dispute = true })
  Net.Sync()
  local first = Take()
  EQ(#first, 1, "one message to the guild: only the shareable ignore record")
  EQ(first[1].prefix, PREFIX, "on the community prefix")
  EQ(first[1].channel, "GUILD", "to the guild channel")
  EQ(first[1].target, nil, "with no target")
  local message = Parse(first[1])
  EQ(message.kind, "R1", "a report")
  EQ(#message.items, 1, "with one record")
  EQ(message.items[1].hash, HashFor("Bad One"), "naming the target only by its hash")
  EQ(message.items[1].mask, ns.Const.LabelValue.scam + ns.Const.LabelValue.toxicity, "and its labels")
  EQ(message.items[1].token, Hash.Token(ns.db.community.install.secret, HashFor("Bad One")), "and the install's anonymous token")
  OK(not first[1].text:find("Bad") and not first[1].text:find("private"), "no name or comment is sent")
  EQ(ns.db.community.sent.guild[HashFor("Bad One")], message.items[1].mask, "the announcement is remembered")
  Net.Sync()
  Advance(5)
  EQ(#Take(), 0, "syncing again sends nothing new")

  -- A change retracts and re-reports; a removal retracts.
  Rec("Bad One", "ignore", { scam = true })
  Net.Sync()
  Advance(5)
  local changed = Take()
  EQ(#changed, 2, "a changed label set is a retraction and a new report")
  EQ(Parse(changed[1]).kind, "X1", "the retraction goes first")
  EQ(Parse(changed[2]).kind, "R1", "then the report")
  EQ(Parse(changed[2]).items[1].mask, ns.Const.LabelValue.scam, "with the new labels")
  ns.Records.Remove("Bad One")
  Net.Sync()
  Advance(5)
  local removed = Take()
  EQ(#removed, 1, "removing the record sends one message")
  EQ(Parse(removed[1]).kind, "X1", "a retraction")
  EQ(Parse(removed[1]).items[1].token, Hash.Token(ns.db.community.install.secret, HashFor("Bad One")), "for that target's token")
  EQ(next(ns.db.community.sent.guild), nil, "and nothing is remembered as announced")
  Rec("Soon Warn", "ignore", { spam = true })
  Net.Sync()
  Advance(5)
  Take()
  Rec("Soon Warn", "warn", { spam = true })
  Net.Sync()
  Advance(5)
  EQ(Parse(Take()[1]).kind, "X1", "turning an ignore into a warn withdraws the report")

  -- Not in a guild: nothing goes to the guild.
  Fresh()
  Consent.SetToggle("guild", "send", true)
  inGuild = false
  Rec("Bad One", "ignore", { scam = true })
  Net.Sync()
  EQ(#Take(), 0, "without a guild there is nowhere to send")

  -- Queue: six to a message, half a second apart, one pending slot per target.
  Fresh()
  Consent.SetToggle("guild", "send", true)
  for index = 1, 14 do Rec("Player" .. string.char(64 + index), "ignore", { scam = true }) end
  Net.Sync()
  local firstOut = Take()
  EQ(#firstOut, 1, "only one message goes out at once")
  Advance(0.4)
  EQ(#Take(), 0, "the next waits for the gap")
  Advance(0.2)
  local second = Take()
  EQ(#second, 1, "the next goes out after half a second")
  Advance(1)
  local third = Take()
  EQ(#Parse(firstOut[1]).items + #Parse(second[1]).items + #Parse(third[1]).items, 14, "fourteen records in three messages")
  OK(third[1].at - second[1].at >= 0.5, "messages are at least half a second apart")
  EQ(Net.PendingCount(), 0, "the queue is empty afterwards")

  -- Failed sends are retried three times, then dropped.
  Fresh()
  Consent.SetToggle("guild", "send", true)
  sendOk = false
  Rec("Bad One", "ignore", { scam = true })
  Net.Sync()
  EQ(Net.PendingCount(), 1, "a failed message waits")
  Advance(5.1)
  EQ(Net.PendingCount(), 1, "and is retried")
  Advance(5.1)
  EQ(Net.PendingCount(), 0, "and dropped after the third failure")
  sendOk = true
  Advance(10)
  EQ(#Take(), 0, "nothing was sent while sending failed")
  Net.Sync()
  local again = Take()
  EQ(#again, 1, "a report that was dropped is not marked as announced, so the next sync sends it again")
  EQ(Parse(again[1]).kind, "R1", "as a report")

  -- A newer report replaces an unsent one.
  Fresh()
  Consent.SetToggle("guild", "send", true)
  sendOk = false
  Rec("Bad One", "ignore", { scam = true })
  Net.Sync()
  Rec("Bad One", "ignore", { scam = true, spam = true })
  Net.Sync()
  Rec("Bad One", "ignore", { scam = true, spam = true, hate = true })
  Net.Sync()
  local queued = Net.PendingCount()
  OK(queued <= 2, "unsent reports for one target are replaced, not piled up (" .. queued .. ")")
  sendOk = true
  Advance(6)
  local latest = Take()
  local lastReport
  for _, item in ipairs(latest) do if Parse(item).kind == "R1" then lastReport = Parse(item) end end
  EQ(lastReport.items[1].mask, ns.Const.LabelValue.scam + ns.Const.LabelValue.spam + ns.Const.LabelValue.hate, "the newest labels are what finally goes out")

  -- Switching on later sends the whole backlog.
  Fresh()
  Rec("Bad One", "ignore", { scam = true })
  Rec("Bad Two", "ignore", { spam = true })
  Net.Reset()
  Consent.SetToggle("guild", "send", true)
  Net.Changed()
  Advance(1.1)
  Advance(2)
  local backlog = Take()
  local carried = 0
  for _, item in ipairs(backlog) do carried = carried + #Parse(item).items end
  EQ(carried, 2, "switching the guild switch on sends everything there is")
  Net.Changed()
  Advance(3)
  OK(#Take() == 0, "a later change without a switch change does not repeat the backlog")

  -- Receiving from the guild.
  Fresh()
  Consent.SetToggle("guild", "receive", true)
  local spy = Spy()
  local H = HashOf(11)
  local report = "R1\t" .. H .. ":" .. ns.Const.LabelValue.scam .. ":" .. today .. ":" .. TokenOf(1)
  Net.OnMessage(PREFIX, report, "GUILD", "Carol Three")
  local stored = ns.db.community.reports.guild and ns.db.community.reports.guild[H]
  OK(stored ~= nil and stored.scam[TokenOf(1)] == today, "a guild report is filed under the guild source")
  EQ(ns.db.community.reports.friends, nil, "and not under friends")
  EQ(spy.n, 0, "listeners hear about it after a moment, not at once")
  Advance(1.1)
  EQ(spy.n, 1, "and once for any number of reports")
  OK(next(ns.db.community.reports.guild[H].scam) == TokenOf(1), "the sender is not stored: only the token")
  local serialized = {}
  local function Walk(value)
    if type(value) == "table" then for k, v in pairs(value) do serialized[#serialized + 1] = tostring(k); Walk(v) end
    else serialized[#serialized + 1] = tostring(value) end
  end
  Walk(ns.db.community.reports)
  OK(not table.concat(serialized, " "):find("Carol"), "nothing in the store names the sender")

  -- Receiving checks.
  local function Count() local tokens = Aggregate.Counts(); return tokens end
  local before = Count()
  Net.OnMessage("OTHER", report, "GUILD", "Carol Three")
  Net.OnMessage(PREFIX, report, "SAY", "Carol Three")
  Net.OnMessage(PREFIX, report, "PARTY", "Carol Three")
  Net.OnMessage(PREFIX, report, "GUILD", "Alice One")
  Net.OnMessage(PREFIX, report, "GUILD", nil)
  Net.OnMessage(PREFIX, report .. string.rep("x", 300), "GUILD", "Carol Three")
  Net.OnMessage(PREFIX, "R1\tgarbage", "GUILD", "Carol Three")
  Net.OnMessage(PREFIX, "R1\t" .. string.upper(HashOf(10)) .. ":1:" .. today .. ":" .. TokenOf(2), "GUILD", "Carol Three")
  Net.OnMessage(PREFIX, "R1\t" .. H .. ":1:" .. (today - 200) .. ":" .. TokenOf(3), "GUILD", "Carol Three")
  Net.OnMessage(PREFIX, "R1\t" .. H .. ":1:" .. (today + 9) .. ":" .. TokenOf(4), "GUILD", "Carol Three")
  issecretvalue = function(value) return value == SECRET end
  Net.OnMessage(PREFIX, "R1\t" .. H .. ":1:" .. today .. ":" .. TokenOf(5), "GUILD", SECRET)
  Net.OnMessage(PREFIX, SECRET, "GUILD", "Carol Three")
  issecretvalue = nil
  EQ(Count(), before, "wrong prefix, channel, sender, size, hash, day and secret values add nothing")

  -- Whispers need a friend and the friends switch.
  friendList = { { name = "Dave Four", connected = true } }
  Roster.Reset()
  local friendReport = "R1\t" .. HashOf(12) .. ":1:" .. today .. ":" .. TokenOf(6)
  Net.OnMessage(PREFIX, friendReport, "WHISPER", "Dave Four")
  EQ(ns.db.community.reports.friends, nil, "friend reports are refused while the friends switch is off")
  Consent.SetToggle("friends", "receive", true)
  Net.OnMessage(PREFIX, friendReport, "WHISPER", "Stranger Five")
  EQ(ns.db.community.reports.friends, nil, "a whisper from someone who is not a friend is refused")
  Net.OnMessage(PREFIX, friendReport, "WHISPER", "Dave Four")
  OK(ns.db.community.reports.friends and ns.db.community.reports.friends[HashOf(12)], "a friend's report is filed under friends")
  EQ(ns.db.community.reports.guild[HashOf(12)], nil, "and not under the guild")
  Consent.SetToggle("guild", "receive", false)
  Net.OnMessage(PREFIX, report, "GUILD", "Carol Three")
  EQ(ns.db.community.reports.guild[H].scam[TokenOf(1)], today, "a switched-off source accepts no new reports")
  Net.OnMessage(PREFIX, "R1\t" .. HashOf(13) .. ":1:" .. today .. ":" .. TokenOf(7), "GUILD", "Carol Three")
  EQ(ns.db.community.reports.guild[HashOf(13)], nil, "(checked with a fresh target)")

  -- Retractions only touch their own source.
  Consent.SetToggle("guild", "receive", true)
  ns.Aggregate.Add(HashOf(14), 1, today, TokenOf(8), "guild")
  ns.Aggregate.Add(HashOf(14), 1, today, TokenOf(8), "friends")
  Net.OnMessage(PREFIX, "X1\t" .. HashOf(14) .. ":" .. TokenOf(8), "GUILD", "Carol Three")
  EQ(ns.db.community.reports.guild[HashOf(14)], nil, "a guild retraction removes the guild report")
  OK(ns.db.community.reports.friends[HashOf(14)] ~= nil, "and leaves the friends report")
  ns.Aggregate.Add(HashOf(14), 1, today, TokenOf(8), "guild")
  Net.OnMessage(PREFIX, "X1	" .. HashOf(14) .. ":" .. TokenOf(8), "WHISPER", "Dave Four")
  EQ(ns.db.community.reports.friends[HashOf(14)], nil, "a friend's retraction removes the friends report")
  OK(ns.db.community.reports.guild[HashOf(14)] ~= nil, "and leaves the guild report")

  -- Rate caps per sender: 30 a minute, 600 an hour.
  Fresh()
  Consent.SetToggle("guild", "receive", true)
  local function Burst(sender, from, count)
    for index = from, from + count - 1 do
      Net.OnMessage(PREFIX, "R1\t" .. HashOf(1000 + index) .. ":1:" .. today .. ":" .. TokenOf(index), "GUILD", sender)
    end
  end
  Burst("Spammer Six", 1, 40)
  EQ(Count(), 30, "a sender gets 30 records a minute")
  Advance(61)
  Burst("Spammer Six", 41, 5)
  EQ(Count(), 35, "and more once the minute is over")
  Burst("Helper Seven", 100, 3)
  EQ(Count(), 38, "other senders have their own allowance")
  local oldMinute, oldHour = ns.Const.Community.perMinute, ns.Const.Community.perHour
  ns.Const.Community.perMinute, ns.Const.Community.perHour = 1000, 40
  Burst("Flood Eight", 200, 60)
  EQ(Count(), 38 + 40, "the hourly cap holds as well")
  ns.Const.Community.perMinute, ns.Const.Community.perHour = oldMinute, oldHour

  -- Friends: hello, reply, confirmation, backlog, and deltas.
  Fresh()
  Consent.SetToggle("friends", "send", true)
  Consent.SetToggle("friends", "receive", true)
  Rec("Bad One", "ignore", { scam = true })
  friendList = { { name = "Dave Four", connected = true }, { name = "Erin Five", connected = false } }
  Roster.Reset()

  -- Hello replies: H1 from a friend is answered once a minute, only when we receive.
  Net.OnMessage(PREFIX, "H1", "WHISPER", "Dave Four")
  Advance(1)
  local reply = Take()
  EQ(#reply, 1, "a hello from a friend is answered")
  EQ(reply[1].text, "H2", "with H2")
  EQ(reply[1].channel, "WHISPER", "by whisper")
  EQ(reply[1].target, "Dave Four", "to that friend")
  Net.OnMessage(PREFIX, "H1", "WHISPER", "Dave Four")
  Advance(1)
  EQ(#Take(), 0, "a second hello within a minute is not answered")
  Advance(61)
  Net.OnMessage(PREFIX, "H1", "WHISPER", "Dave Four")
  Advance(1)
  EQ(#Take(), 1, "after a minute it is answered again")
  Net.OnMessage(PREFIX, "H1", "WHISPER", "Stranger Five")
  Net.OnMessage(PREFIX, "H1", "GUILD", "Dave Four")
  Advance(1)
  EQ(#Take(), 0, "hellos from strangers or over the guild channel are ignored")
  Consent.SetToggle("friends", "receive", false)
  Advance(61)
  Net.OnMessage(PREFIX, "H1", "WHISPER", "Dave Four")
  Advance(1)
  EQ(#Take(), 0, "without the receive switch we do not even say that we run the addon")
  Consent.SetToggle("friends", "receive", true)

  -- H2 confirms a friend, who then gets the backlog and later changes.
  Net.OnMessage(PREFIX, "H2", "WHISPER", "Stranger Five")
  Advance(1)
  EQ(#Take(), 0, "a reply from a stranger confirms nobody")
  Net.OnMessage(PREFIX, "H2", "WHISPER", "Dave Four")
  Advance(1)
  local welcome = Take()
  EQ(#welcome, 1, "a confirmed friend gets the backlog")
  EQ(welcome[1].target, "Dave Four", "by whisper")
  EQ(Parse(welcome[1]).items[1].hash, HashFor("Bad One"), "naming only hashes")
  Rec("Another One", "ignore", { spam = true })
  Net.Sync()
  Advance(1)
  local delta = Take()
  EQ(#delta, 1, "a new record goes to the confirmed friend")
  EQ(delta[1].target, "Dave Four", "and only to the confirmed online friend, not to Erin")
  local deltaHashes = {}
  for _, item in ipairs(Parse(delta[1]).items) do deltaHashes[item.hash] = true end
  OK(deltaHashes[HashFor("Another One")], "and it carries the new record")
  friendList[1].connected = false
  Roster.Reset()
  Rec("Third One", "ignore", { hate = true })
  Net.Sync()
  Advance(1)
  EQ(#Take(), 0, "an offline friend is not sent anything")
  Consent.SetToggle("friends", "send", false)
  Net.OnMessage(PREFIX, "H2", "WHISPER", "Dave Four")
  Advance(1)
  EQ(#Take(), 0, "a hello reply is ignored while sending to friends is off")

  -- Registration wires everything up.
  Fresh()
  local frames = {}
  local savedCreate = CreateFrame
  CreateFrame = function()
    local frame = { events = {}, scripts = {} }
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:SetScript(name, fn) self.scripts[name] = fn end
    frames[#frames + 1] = frame
    return frame
  end
  C_Timer = { After = function() end }
  local prefixes = {}
  C_ChatInfo = { RegisterAddonMessagePrefix = function(prefix) prefixes[#prefixes + 1] = prefix return true end }
  Net.Reset()
  OK(Net.Register(), "registration succeeds when the client has what it needs")
  EQ(prefixes[1], PREFIX, "the community prefix is registered")
  local listener
  for _, frame in ipairs(frames) do if frame.events.CHAT_MSG_ADDON then listener = frame end end
  OK(listener ~= nil, "the addon message event is listened to")
  Consent.SetToggle("guild", "receive", true)
  listener.scripts.OnEvent(listener, "CHAT_MSG_ADDON", PREFIX, report, "GUILD", "Carol Three")
  OK(ns.db.community.reports.guild and ns.db.community.reports.guild[H], "an event reaches the receiving code")
  OK(Net.Register(), "registering twice is harmless")
  C_ChatInfo = nil
  CreateFrame = savedCreate
  C_Timer = nil

  UnitName, C_FriendList, IsInGuild = nil, nil, nil
end)

-- --- Community: revoke sends retractions and wipes data (section 8.9) ------------------------------

Group("Revoke", function()
  local Net, Consent, Roster, Hash, Report = ns.Net, ns.Consent, ns.Roster, ns.Hash, ns.Report
  local sent, timers, now = {}, {}, 0
  Net.io = {
    send = function(prefix, text, channel, target) sent[#sent + 1] = { text = text, channel = channel, target = target } return true end,
    after = function(delay, fn) timers[#timers + 1] = { at = now + delay, fn = fn } end,
    now = function() return now end,
    serverTime = function() return 1700000000 end,
  }
  local function Advance(seconds)
    local limit = now + seconds
    repeat
      local pick
      for index, timer in ipairs(timers) do
        if timer.at <= limit and (not pick or timer.at < timers[pick].at) then pick = index end
      end
      if pick then
        local timer = table.remove(timers, pick)
        now = math.max(now, timer.at)
        timer.fn()
      end
    until not pick
    now = limit
  end
  FreshDb()
  Net.Reset()
  UnitName = function(unit) if unit == "player" then return "Alice", "One" end end
  IsInGuild = function() return true end
  Consent.Confirm()
  Consent.SetToggle("guild", "send", true)
  Consent.SetToggle("guild", "receive", true)
  ns.Records.Save("Bad One", "ignore", { scam = true }, "c")
  Net.Sync()
  Advance(2)
  sent = {}
  ns.Aggregate.Add(HashOf(1), 1, Hash.Day(1700000000), TokenOf(1), "guild")

  Consent.Revoke()
  Advance(2)
  local retractions = 0
  for _, message in ipairs(sent) do
    local parsed = Report.Parse(message.text, Hash.Day(1700000000))
    if parsed and parsed.kind == "X1" then retractions = retractions + #parsed.items end
  end
  EQ(retractions, 1, "revoking withdraws what was reported")
  EQ(Consent.Active(), false, "consent is gone")
  EQ(ns.Aggregate.Counts(), 0, "received reports are deleted")
  sent = {}
  ns.Records.Save("Another One", "ignore", { spam = true }, "c")
  Net.Sync()
  Advance(2)
  EQ(#sent, 0, "and nothing is sent afterwards")
  UnitName, IsInGuild = nil, nil
end)

-- --- Localization: German is complete and matches English (section 10) ------------------------

Group("Locale parity", function()
  -- run.lua only loads the English table, so load the German one on the side.
  local en, de = ns.Locale.Tables.en, ns.Locale.Tables.de

  local missing, extra = {}, {}
  for key in pairs(en) do if rawget(de, key) == nil then missing[#missing + 1] = key end end
  for key in pairs(de) do if rawget(en, key) == nil then extra[#extra + 1] = key end end
  table.sort(missing)
  table.sort(extra)
  EQ(table.concat(missing, ","), "", "every English key has a German text")
  EQ(table.concat(extra, ","), "", "German has no keys English lacks")

  -- A German text must take the same arguments as the English one.
  local function Specifiers(text)
    local list = {}
    for spec in text:gmatch("%%[sd]") do list[#list + 1] = spec end
    return table.concat(list, " ")
  end
  local mismatched = {}
  for key, text in pairs(en) do
    local german = rawget(de, key)
    if german and Specifiers(text) ~= Specifiers(german) then mismatched[#mismatched + 1] = key end
  end
  table.sort(mismatched)
  EQ(table.concat(mismatched, ","), "", "German texts take the same format arguments as English")
  local blank = {}
  for key, text in pairs(de) do if type(text) ~= "string" or text == "" then blank[#blank + 1] = key end end
  EQ(#blank, 0, "no German text is empty")

  -- Every key the code asks for exists, so a typo is caught here and not in game.
  local toc = assert(io.open(root .. "/NullgatesBlacklist-Forever/NullgatesBlacklist-Forever.toc", "rb"))
  local tocText = toc:read("*a")
  toc:close()
  local unknown, seen = {}, {}
  for file in tocText:gmatch("([%w/_]+%.lua)") do
    local handle = assert(io.open(root .. "/NullgatesBlacklist-Forever/" .. file, "rb"))
    local source = handle:read("*a")
    handle:close()
    if not file:find("^Locale/") then
      for key in source:gmatch('Text%("([A-Z][A-Z0-9_]+)"%)') do
        if en[key] == nil and not seen[key] then seen[key] = true; unknown[#unknown + 1] = file .. ":" .. key end
      end
      for key in source:gmatch('"([A-Z][A-Z0-9_]*)"') do
        if (key:find("^ERR_") or key:find("^MSG_") or key:find("^OPT_")) and en[key] == nil and not seen[key] then
          seen[key] = true
          unknown[#unknown + 1] = file .. ":" .. key
        end
      end
    end
  end
  table.sort(unknown)
  EQ(table.concat(unknown, ", "), "", "every locale key used in the code exists")
end)

-- --- Settings: saved data of every age is made whole, nothing the player set is lost -------------

Group("Settings migration", function()
  local Settings = ns.Settings
  local function Run(saved)
    NullgatesBlacklistDB = saved
    local db, state = Settings.Init()
    return db, state
  end

  local db = Run(nil)
  EQ(db.version, 1, "empty data becomes version 1")
  EQ(db.settings.language, "auto", "with the default language")
  EQ(db.settings.replyMode, "none", "and the reply off")
  EQ(db.settings.setupDone, false, "and the wizard still to show")
  OK(db.settings.export.id:match("^%x+$") and #db.settings.export.id == 12, "a 12 digit export id is made")
  OK(db.community.install.secret:match("^%x+$") and #db.community.install.secret == 32, "a 32 digit install secret is made")
  OK(type(db.records) == "table" and type(db.subscriptions) == "table", "the tables exist")
  OK(type(db.community.reports) == "table" and type(db.community.hidden) == "table", "the community tables exist")
  EQ(db.settings.community.guild.send, false, "community switches are off")
  EQ(db.settings.community.consentVersion, 0, "and nothing is confirmed")

  local id, secret = db.settings.export.id, db.community.install.secret
  Run(NullgatesBlacklistDB)
  EQ(ns.db.settings.export.id, id, "starting again keeps the export id")
  EQ(ns.db.community.install.secret, secret, "and the install secret")

  -- Old and partial data keeps what the player chose and gains what is new.
  db = Run({ settings = { hideChat = false, language = "de", replyMode = "labels",
    community = { rules = { { label = "scam", source = "guild", minTier = 2, verdict = "warn" } } } },
    records = { ["a b"] = { name = "A B", verdict = "ignore", labels = { spam = true }, comment = "c" } } })
  EQ(db.version, 1, "unversioned data is migrated")
  EQ(db.settings.hideChat, false, "a changed setting is kept")
  EQ(db.settings.language, "de", "the language is kept")
  EQ(db.settings.replyMode, "labels", "the reply mode is kept")
  EQ(db.settings.autoDecline, true, "a missing setting gets its default")
  EQ(#db.settings.community.rules, 1, "the player's rules are kept")
  EQ(db.settings.community.guild.send, false, "a missing nested setting gets its default")
  EQ(db.records["a b"].comment, "c", "records are kept")
  OK(db.community.install.secret ~= nil, "and an install secret appears")

  -- Damaged data is repaired instead of crashing.
  db = Run({ version = 1, settings = { export = "junk", community = 5 }, community = { install = "x" } })
  EQ(type(db.settings.export), "table", "a broken export table is replaced")
  OK(#db.settings.export.id == 12, "with a new id")
  EQ(type(db.settings.community), "table", "a broken community table is replaced")
  EQ(#db.community.install.secret, 32, "a broken install table is replaced with a new secret")
  db = Run({ version = 1, settings = { export = { id = "nothex!" } }, community = { install = { secret = "short" } } })
  OK(db.settings.export.id:match("^%x+$") ~= nil and #db.settings.export.id == 12, "a bad export id is replaced")
  EQ(#db.community.install.secret, 32, "a bad secret is replaced")
  db = Run({ version = 1 })
  OK(type(db.settings) == "table" and type(db.community) == "table", "data without settings or community is completed")

  -- Newer data is left alone.
  local newer = { version = 99, settings = { hideChat = "stay" }, records = { x = 1 } }
  local _, state = Run(newer)
  EQ(state, "newer", "data from a later build is reported")
  EQ(ns.db, nil, "and not loaded, so nothing can modify it")
  EQ(newer.settings.hideChat, "stay", "it is untouched")
  EQ(newer.version, 99, "and keeps its version")
  NullgatesBlacklistDB = nil
  Settings.Init()
end)

-- --- Enforce/Reply: the optional automatic reply (section 6.4) --------------------------------------

Group("Reply", function()
  local Reply, Settings, Records, Const = ns.Reply, ns.Settings, ns.Records, ns.Const
  local now, timers, sent = 0, {}, {}
  local sendOk = true
  Reply.io = {
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
    repeat
      local pick
      for index, timer in ipairs(timers) do
        if timer.at <= limit and (not pick or timer.at < timers[pick].at) then pick = index end
      end
      if pick then
        local timer = table.remove(timers, pick)
        now = math.max(now, timer.at)
        timer.fn()
      end
    until not pick
    now = limit
  end
  local function Fresh(mode)
    FreshDb()
    Reply.Reset()
    UnitName = function(unit) if unit == "player" then return "Self", "Char" end end
    sent, timers, printed, sendOk = {}, {}, {}, true
    Settings.Set("replyMode", mode or "none")
  end

  -- Off by default.
  Fresh("none")
  Records.Save("Rude One", "ignore", { toxicity = true, spam = true }, "my private comment")
  Reply.OnWhisper("hello", "Rude One")
  Advance(5)
  EQ(#sent, 0, "with the reply off nothing is sent")

  -- Short reply: after a delay, once per player and session.
  Fresh("short")
  Records.Save("Rude One", "ignore", { toxicity = true, spam = true }, "my private comment")
  Reply.OnWhisper("hello", "Rude One")
  EQ(#sent, 0, "nothing is sent at once")
  Advance(1.4)
  EQ(#sent, 0, "nor before 1.5 seconds")
  Advance(0.2)
  EQ(#sent, 1, "the reply goes out after 1.5 seconds")
  EQ(sent[1].text, ns.L.REPLY_SHORT, "with the short sentence")
  EQ(sent[1].target, "Rude One", "to the player")
  Reply.OnWhisper("hello again", "Rude One")
  Reply.OnWhisper("hello?", "rude one")
  Advance(5)
  EQ(#sent, 1, "a player gets one reply per session, whatever the spelling")
  Records.Save("Rude Two", "ignore", { spam = true }, "c")
  Reply.OnWhisper("hi", "Rude Two")
  Advance(2)
  EQ(#sent, 2, "another player gets their own reply")
  Reply.Reset()
  Reply.OnWhisper("hi", "Rude One")
  Advance(2)
  EQ(#sent, 3, "a new session answers again")

  -- The reasons variant names the labels and never the comment.
  Fresh("labels")
  Records.Save("Rude One", "ignore", { toxicity = true, spam = true }, "my private comment")
  Reply.OnWhisper("hello", "Rude One")
  Advance(2)
  OK(sent[1].text:find(ns.L.LABEL_TOXICITY, 1, true) ~= nil, "the reasons reply names a label")
  OK(sent[1].text:find(ns.L.LABEL_SPAM, 1, true) ~= nil, "and the other")
  OK(not sent[1].text:find("private", 1, true) and not sent[1].text:find("comment", 1, true), "but never the comment")
  OK(#sent[1].text <= 250, "and stays within 250 bytes")

  -- Only an ignore from an own record is answered.
  Fresh("short")
  Records.Save("Warned One", "warn", { spam = true }, "c")
  Reply.OnWhisper("hi", "Warned One")
  ns.Subscriptions.Import({ id = "abc123", name = "L", author = "X Y", count = 1, records = {
    ["listed one"] = { name = "Listed One", labels = { spam = true }, comment = "c" } } })
  ns.Subscriptions.SetRule("abc123", "spam", "ignore")
  EQ(ns.Resolver.Verdict("Listed One"), "ignore", "(an imported list ignores this player)")
  Reply.OnWhisper("hi", "Listed One")
  Reply.OnWhisper("hi", "Stranger One")
  Reply.OnWhisper("hi", "Self Char")
  issecretvalue = function(value) return value == SECRET end
  Reply.OnWhisper("hi", SECRET)
  Reply.OnWhisper(SECRET, "Rude One")
  issecretvalue = nil
  Reply.OnWhisper("hi", nil)
  Advance(5)
  EQ(#sent, 0, "warn, imported-list, unknown, own and secret senders get no reply")
  Records.Save("Rude One", "ignore", { spam = true }, "c")
  Reply.OnWhisper("hi", "Rude One")
  Advance(2)
  EQ(#sent, 1, "an own ignore record does")

  -- The echo of our own reply is hidden for 15 seconds.
  EQ(Reply.Filter(nil, "CHAT_MSG_WHISPER_INFORM", sent[1].text), true, "our own reply is hidden from the chat")
  EQ(Reply.Filter(nil, "CHAT_MSG_WHISPER_INFORM", sent[1].text .. " (edited tail)"), true, "matched by its first words")
  EQ(Reply.Filter(nil, "CHAT_MSG_WHISPER_INFORM", "something I typed myself"), false, "a message I typed is shown")
  Advance(13)
  EQ(Reply.Filter(nil, "CHAT_MSG_WHISPER_INFORM", sent[1].text), true, "still hidden after 13 seconds")
  Advance(3)
  EQ(Reply.Filter(nil, "CHAT_MSG_WHISPER_INFORM", sent[1].text), false, "shown again after 15 seconds")
  issecretvalue = function(value) return value == SECRET end
  EQ(Reply.Filter(nil, "CHAT_MSG_WHISPER_INFORM", SECRET), false, "a secret message is never touched")
  issecretvalue = nil

  -- A failing send is reported once.
  Fresh("short")
  Records.Save("Rude One", "ignore", { spam = true }, "c")
  Records.Save("Rude Two", "ignore", { spam = true }, "c")
  sendOk = false
  Reply.OnWhisper("hi", "Rude One")
  Reply.OnWhisper("hi", "Rude Two")
  Advance(3)
  local failures = 0
  for _, line in ipairs(printed) do if line:find(ns.L.MSG_REPLY_FAILED, 1, true) then failures = failures + 1 end end
  EQ(failures, 1, "a failed send is reported once, however often it happens")

  -- Long reasons are cut on a character boundary.
  Fresh("labels")
  local saved = ns.L.LABEL_TOXICITY
  ns.L.LABEL_TOXICITY = string.rep("\195\164", 200)
  Records.Save("Rude One", "ignore", { toxicity = true }, "c")
  Reply.OnWhisper("hi", "Rude One")
  Advance(2)
  OK(#sent[1].text <= 250, "a long reply is cut to 250 bytes")
  local tail = sent[1].text:match("[\195\164]+$")
  OK(tail ~= nil and #tail % 2 == 0, "without splitting an umlaut")
  ns.L.LABEL_TOXICITY = saved

  -- The preview line on the settings tab and in the wizard.
  local Control = ns.ReplyControl
  EQ(Control.PreviewText("none"), ns.L.OPT_REPLY_OFF, "no preview sentence while off")
  OK(Control.PreviewText("short"):find(ns.L.REPLY_SHORT, 1, true) ~= nil, "the short preview shows the sentence")
  local withReasons = Control.PreviewText("labels")
  OK(withReasons:find(ns.L.LABEL_TOXICITY, 1, true) and withReasons:find(ns.L.LABEL_SPAM, 1, true), "the reasons preview shows sample reasons")

  -- Registration listens for whispers and filters the echo.
  Fresh("short")
  local frames, filters = {}, {}
  local savedCreate, savedTimer, savedAdd = CreateFrame, C_Timer, ChatFrame_AddMessageEventFilter
  CreateFrame = function()
    local frame = { events = {}, scripts = {} }
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:SetScript(name, fn) self.scripts[name] = fn end
    frames[#frames + 1] = frame
    return frame
  end
  C_Timer = { After = function() end }
  ChatFrame_AddMessageEventFilter = function(event, fn) filters[event] = fn end
  OK(Reply.Register(), "registration succeeds")
  OK(frames[1] and frames[1].events.CHAT_MSG_WHISPER, "whispers are listened to")
  EQ(filters.CHAT_MSG_WHISPER_INFORM, Reply.Filter, "the echo filter is installed")
  Records.Save("Rude One", "ignore", { spam = true }, "c")
  frames[1].scripts.OnEvent(frames[1], "CHAT_MSG_WHISPER", "hello", "Rude One")
  EQ(#timers, 1, "a whisper event schedules the reply")
  CreateFrame, C_Timer, ChatFrame_AddMessageEventFilter = savedCreate, savedTimer, savedAdd
  UnitName = nil
end)

-- --- Net: the self test behind "/nbl check" ---------------------------------------------------------------

Group("Net self test", function()
  local Net, Const = ns.Net, ns.Const
  local PREFIX = Const.COMMUNITY_PREFIX
  local now, timers, sent = 0, {}, {}
  local sendOk = true
  Net.io = {
    send = function(prefix, text, channel, target)
      if not sendOk then return false end
      sent[#sent + 1] = { prefix = prefix, text = text, channel = channel, target = target }
      return true
    end,
    after = function(delay, fn) timers[#timers + 1] = { at = now + delay, fn = fn } end,
    now = function() return now end,
    serverTime = function() return 1700000000 end,
  }
  local function Advance(seconds)
    local limit = now + seconds
    repeat
      local pick
      for index, timer in ipairs(timers) do
        if timer.at <= limit and (not pick or timer.at < timers[pick].at) then pick = index end
      end
      if pick then
        local timer = table.remove(timers, pick)
        now = math.max(now, timer.at)
        timer.fn()
      end
    until not pick
    now = limit
  end
  local function Fresh()
    FreshDb()
    Net.Reset()
    UnitName = function(unit) if unit == "player" then return "Alice", "One" end end
    sent, timers, sendOk = {}, {}, true
  end
  local result
  local function Done(ok, reason) result = { ok = ok, reason = reason } end

  -- It works: the message goes to our own name and comes back.
  Fresh()
  result = nil
  Net.SelfTest(Done)
  EQ(#sent, 1, "one message is sent")
  EQ(sent[1].prefix, PREFIX, "on the community prefix")
  EQ(sent[1].channel, "WHISPER", "as a whisper")
  EQ(sent[1].target, "Alice One", "to the player's own name")
  local nonce = sent[1].text:match("^T1\t(%x%x%x%x%x%x%x%x)$")
  OK(nonce ~= nil, "carrying a random 8 digit code")
  EQ(result, nil, "no verdict before the message comes back")
  Net.OnMessage(PREFIX, "T1\t" .. string.rep("0", 8), "WHISPER", "Alice One")
  EQ(result, nil, "a different code is not our message")
  Net.OnMessage(PREFIX, "T1\t" .. nonce, "GUILD", "Alice One")
  EQ(result, nil, "nor is the same code on another channel")
  Net.OnMessage(PREFIX, "T1\t" .. nonce, "WHISPER", "Mallory Two")
  EQ(result, nil, "nor from another player")
  Net.OnMessage(PREFIX, "T1\t" .. nonce, "WHISPER", "Alice One")
  EQ(result and result.ok, true, "the echo from our own name passes the test")
  result = nil
  Net.OnMessage(PREFIX, "T1\t" .. nonce, "WHISPER", "Alice One")
  EQ(result, nil, "and counts only once")
  Advance(5)
  EQ(result, nil, "the timeout does not fire afterwards")

  -- Nothing comes back.
  Fresh()
  result = nil
  Net.SelfTest(Done)
  Advance(2.9)
  EQ(result, nil, "still waiting after 2.9 seconds")
  Advance(0.2)
  EQ(result and result.ok, false, "no echo within 3 seconds fails the test")
  EQ(result and result.reason, "noecho", "saying that nothing came back")

  -- The client refuses the send.
  Fresh()
  sendOk = false
  result = nil
  Net.SelfTest(Done)
  EQ(result and result.ok, false, "a refused send fails at once")
  EQ(result and result.reason, "refused", "saying the client refused")

  -- Unknown own name.
  Fresh()
  UnitName = nil
  result = nil
  Net.SelfTest(Done)
  EQ(result and result.reason, "refused", "an unknown own name cannot be tested")

  -- One test at a time; another player's T1 never starts or ends anything.
  Fresh()
  local first, second
  Net.SelfTest(function(ok) first = ok end)
  Net.SelfTest(function(ok) second = ok end)
  EQ(#sent, 1, "a second test while one runs does nothing")
  Net.OnMessage(PREFIX, "T1\t" .. sent[1].text:match("(%x%x%x%x%x%x%x%x)$"), "WHISPER", "Bob Two")
  EQ(first, nil, "another player cannot answer our test")
  EQ(second, nil, "and the ignored second test never reports")
  Net.OnMessage(PREFIX, "T1\tzzzzzzzz", "WHISPER", "Bob Two")
  UnitName = nil
  Net.Reset()
end)

-- --- Locale: registry and the immediate switch (section 10) ------------------------------------------------

Group("Locale registry", function()
  local Locale, Settings = ns.Locale, ns.Settings
  FreshDb()
  EQ(table.concat(Locale.Order, ","), "en,de", "English comes first, then the other languages")
  EQ(Locale.Names.en, "English", "a language is shown under its own name")
  EQ(Locale.Names.de, "Deutsch", "German too")
  EQ(Locale.Base, Locale.Tables.en, "English is the base every language falls back to")

  EQ(Locale.IsValid("auto"), true, "auto is valid")
  EQ(Locale.IsValid("de"), true, "a registered code is valid")
  EQ(Locale.IsValid("xx"), false, "an unknown code is not")
  EQ(Locale.IsValid(nil), false, "nil is not")
  EQ(Locale.IsValid(5), false, "a number is not")

  local savedLocale = GetLocale
  GetLocale = function() return "deDE" end
  EQ(Locale.Resolve("auto"), "de", "automatic follows a German client")
  EQ(Locale.Resolve(nil), "de", "nothing saved also follows the client")
  GetLocale = function() return "enGB" end
  EQ(Locale.Resolve("auto"), "en", "automatic follows a British English client")
  GetLocale = function() return "frFR" end
  EQ(Locale.Resolve("auto"), "en", "a client language without a translation falls back to English")
  GetLocale = function() return "zhCN" end
  EQ(Locale.Resolve("auto"), "en", "and so does one the addon does not have yet")
  GetLocale = nil
  EQ(Locale.Resolve("auto"), "en", "no GetLocale at all means English")
  EQ(Locale.Resolve("de"), "de", "an explicit choice wins over the client")
  EQ(Locale.Resolve("xx"), "en", "an unknown choice falls back to English")

  -- Choices for the pickers.
  local choices = Locale.Choices()
  EQ(#choices, 3, "automatic plus every language")
  EQ(choices[1].value, "auto", "automatic is first")
  EQ(choices[1].text, ns.L.LANG_AUTO, "under its translated name")
  EQ(choices[2].value .. "/" .. choices[2].text, "en/English", "then English")
  EQ(choices[3].value .. "/" .. choices[3].text, "de/Deutsch", "then German")
  EQ(Locale.NameOf("de"), "Deutsch", "the name of a language")
  EQ(Locale.NameOf("auto"), ns.L.LANG_AUTO, "the name of automatic")

  -- Switching takes effect at once and tells the windows to rebuild.
  local rebuilt = 0
  Locale.OnChange(function() rebuilt = rebuilt + 1 end)
  GetLocale = function() return "enUS" end
  Locale.current = nil
  Settings.Set("language", "auto")
  OK(Locale.Apply(), "applying the first time changes the language")
  EQ(ns.L, Locale.Tables.en, "English is active")
  EQ(rebuilt, 1, "the windows were told to rebuild")
  EQ(Locale.Apply(), false, "applying the same language again changes nothing")
  EQ(rebuilt, 1, "and rebuilds nothing")

  EQ(Locale.Set("de"), "de", "choosing German works")
  EQ(ns.L, Locale.Tables.de, "German is active at once, without a reload")
  EQ(Settings.Get("language"), "de", "and saved")
  EQ(ns.Output.Text("TAB_LIST"), ns.Locale.Tables.de.TAB_LIST, "texts come out in German")
  EQ(rebuilt, 2, "the windows rebuilt once")
  EQ(Locale.Set("de"), "de", "choosing it again is fine")
  EQ(rebuilt, 2, "and does nothing")
  EQ(Locale.Set("xx"), nil, "an unknown language is refused")
  EQ(Settings.Get("language"), "de", "and nothing is saved")
  EQ(ns.L, Locale.Tables.de, "nor changed")
  EQ(Locale.Set("auto"), "auto", "automatic follows the client again")
  EQ(ns.L, Locale.Tables.en, "which is English here")
  EQ(rebuilt, 3, "with another rebuild")

  -- A language only needs the texts it translates: the rest comes from English.
  Locale.Base.TEMPORARY_KEY = "english only"
  EQ(Locale.Tables.de.TEMPORARY_KEY, "english only", "a key missing in German falls back to English")
  Locale.Base.TEMPORARY_KEY = nil

  GetLocale = savedLocale
  Settings.Set("language", "auto")
  Locale.current = nil
  Locale.Apply()
end)

-- --- Widgets: the single-choice picker -------------------------------------------------------------------

Group("Choice picker", function()
  local Widgets = ns.Widgets
  local items = { { value = "a", text = "Alpha" }, { value = "b", text = "Beta" }, { value = "c", text = "Gamma" } }

  -- Dropdown path.
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
  local picked = {}
  local choice = Widgets.Choice({}, items, function(value) picked[#picked + 1] = value end)
  OK(choice ~= nil and choice.frame == dropdown, "the dropdown is used when the client has it")
  EQ(choice.height, 26, "dropdown height")
  choice:SetValue("b")
  EQ(caption, "Beta", "the caption shows the chosen item")
  EQ(choice:GetValue(), "b", "GetValue returns it")
  local radios = {}
  local root = { CreateRadio = function(_, text, isSelected, setSelected)
    radios[#radios + 1] = { text = text, isSelected = isSelected, setSelected = setSelected }
  end }
  generator(dropdown, root)
  EQ(#radios, 3, "one radio entry per item")
  EQ(radios[1].text, "Alpha", "with the item's text")
  EQ(radios[2].isSelected(), true, "the chosen one is selected")
  EQ(radios[1].isSelected(), false, "the others are not")
  radios[3].setSelected()
  EQ(choice:GetValue(), "c", "picking an entry chooses it")
  EQ(caption, "Gamma", "and updates the caption")
  EQ(picked[1], "c", "and tells the caller")
  local checkboxRoot = { CreateCheckbox = function(_, text) radios[#radios + 1] = { text = text } end }
  radios = {}
  generator(dropdown, checkboxRoot)
  EQ(#radios, 3, "without radio entries the menu falls back to checkbox entries")

  -- Grid path: no dropdown, so one checkbox per item and only one ticked.
  local function Stub()
    local widget = { scripts = {} }
    function widget:SetText(text) self.text = text end
    function widget:SetScript(name, fn) self.scripts[name] = fn end
    function widget:SetChecked(value) self.checked = value and true or false end
    function widget:GetChecked() return self.checked end
    function widget:CreateFontString() return Stub() end
    function widget:CreateTexture() return Stub() end
    -- every other client call does nothing
    return setmetatable(widget, { __index = function(_, key) if key == "Text" then return nil end return function() end end })
  end
  local created = {}
  CreateFrame = function(kind, _, _, template)
    if template == "WowStyle1DropdownTemplate" then return nil end
    local widget = Stub()
    created[#created + 1] = widget
    return widget
  end
  MenuResponse = nil
  picked = {}
  local grid = Widgets.Choice({}, items, function(value) picked[#picked + 1] = value end, { columns = 2, columnWidth = 100 })
  OK(grid ~= nil, "a grid is built without a dropdown")
  EQ(grid.height, 48, "three items in two columns take two rows")
  local boxes = {}
  for _, widget in ipairs(created) do if widget.role == "checkbox" then boxes[#boxes + 1] = widget end end
  EQ(#boxes, 3, "one checkbox per item")
  EQ(boxes[2].text, "Beta", "with the item's text")
  grid:SetValue("a")
  EQ(boxes[1].checked, true, "SetValue ticks the item")
  EQ(boxes[2].checked, false, "and unticks the others")
  boxes[3].scripts.OnClick(boxes[3])
  EQ(grid:GetValue(), "c", "clicking a checkbox chooses it")
  EQ(boxes[1].checked, false, "the old choice is unticked")
  EQ(boxes[3].checked, true, "the new one is ticked")
  EQ(picked[1], "c", "and the caller is told")

  CreateFrame = function() return nil end
  EQ(Widgets.Choice({}, items, nil), nil, "without any frame support the picker is nil")
  CreateFrame = nil
  MenuResponse = nil

  -- Window names stay free when a window is rebuilt.
  EQ(Widgets.FrameName("NullgateBlacklistTestWindow"), "NullgateBlacklistTestWindow", "the first window keeps the plain name")
  EQ(Widgets.FrameName("NullgateBlacklistTestWindow"), "NullgateBlacklistTestWindow2", "a rebuilt one gets a new name")
  EQ(Widgets.FrameName("NullgateBlacklistTestWindow"), "NullgateBlacklistTestWindow3", "and again")
end)

-- --- The look: the game's own templates (section 9) ----------------------------------------------------------

-- A stand-in for a client frame that records what the widgets ask of it.
local function Pane(kind, template)
  local pane = { kind = kind, template = template, scripts = {}, shown = true, checked = false, calls = {} }
  function pane:SetText(text) self.text = text end
  function pane:GetText() return self.text or "" end
  function pane:SetScript(name, fn) self.scripts[name] = fn end
  function pane:SetChecked(value) self.checked = value and true or false end
  function pane:GetChecked() return self.checked end
  function pane:SetEnabled(value) self.enabledFlag = value and true or false end
  function pane:Enable() self.enabledFlag = true end
  function pane:Disable() self.enabledFlag = false end
  function pane:Hide() self.shown = false end
  function pane:CreateTexture() return Pane("Texture") end
  function pane:CreateFontString() return Pane("FontString") end
  -- every other client call does nothing
  return setmetatable(pane, { __index = function(_, key) if key == "Text" then return nil end return function() end end })
end

Group("Game-style widgets", function()
  local Widgets = ns.Widgets
  local savedCreate = CreateFrame
  CreateFrame = function(kind, _, _, template) return Pane(kind, template) end
  local parent = Pane("Frame")

  -- Button: the standard red panel button.
  local clicks = 0
  local button = Widgets.Button(parent, "Save", 100, function() clicks = clicks + 1 end)
  EQ(button.template, "UIPanelButtonTemplate", "a button is the game's panel button")
  EQ(button.role, "button", "marked as a button")
  EQ(button.text, "Save", "with its text")
  button.scripts.OnClick(button)
  EQ(clicks, 1, "a click runs the handler")
  Widgets.Button(parent, "No handler", 80).scripts.OnClick({})

  -- Checkbox: the standard check button; its label is part of it.
  local toggled
  local check = Widgets.Checkbox(parent, "Option", function(self) toggled = self:GetChecked() end)
  EQ(check.template, "UICheckButtonTemplate", "a checkbox is the game's check button")
  EQ(check.role, "checkbox", "marked as a checkbox")
  EQ(check.text, "Option", "with its text")
  check:SetChecked(true)
  check.scripts.OnClick(check)
  EQ(toggled, true, "a click runs the handler after the state changed")
  -- Templates that carry their own label text use it.
  CreateFrame = function(kind, _, _, template)
    local pane = Pane(kind, template)
    pane.Text = Pane("FontString")
    return pane
  end
  local labelled = Widgets.Checkbox(parent, "Labelled", nil)
  EQ(labelled.Text.text, "Labelled", "a template with its own text part gets the label there")
  CreateFrame = function(kind, _, _, template) return Pane(kind, template) end

  -- Input box and text area.
  local changes = 0
  local box = Widgets.InputBox(parent, 120, 20, function() changes = changes + 1 end)
  EQ(box.template, "InputBoxTemplate", "an input box is the game's input box")
  EQ(box.role, "input", "marked as an input")
  box.scripts.OnTextChanged(box)
  EQ(changes, 1, "typing runs the change handler")
  local area = Widgets.TextArea(parent, 200, 80, 255)
  EQ(area.edit.role, "textedit", "a text area has its edit box marked")

  -- Tabs: a panel button; the active one is switched off.
  local picked
  local tab = Widgets.TabButton(parent, "Lists", 88, function() picked = true end)
  EQ(tab.template, "UIPanelButtonTemplate", "a tab is a panel button")
  EQ(tab.role, "tab", "marked as a tab")
  tab:SetActive(true)
  EQ(tab.enabledFlag, false, "the active tab is switched off")
  EQ(tab.active, true, "and says so")
  tab:SetActive(false)
  EQ(tab.enabledFlag, true, "an inactive tab can be clicked")
  tab.scripts.OnClick(tab)
  OK(picked, "a click runs the handler")

  -- Windows: the standard framed panel.
  UIParent = Pane("Frame")
  local window = Widgets.Window("NullgateBlacklistWindowTest", 400, 300, "Title")
  EQ(window.template, "BasicFrameTemplateWithInset", "a window is the game's framed panel")
  EQ(window.role, "window", "marked as a window")
  OK(window.scripts.OnDragStart ~= nil and window.scripts.OnDragStop ~= nil, "it can be dragged")
  -- A template without SetTitle keeps its title in a child; the window gets the call anyway.
  CreateFrame = function(kind, _, _, template)
    local pane = Pane(kind, template)
    -- this template has no SetTitle of its own
    getmetatable(pane).__index = function(_, key)
      if key == "SetTitle" or key == "Text" then return nil end
      return function() end
    end
    pane.TitleContainer = { TitleText = Pane("FontString") }
    return pane
  end
  local older = Widgets.Window("NullgateBlacklistWindowTest2", 400, 300, "Old style")
  EQ(older.TitleContainer.TitleText.text, "Old style", "the title goes into the template's title text")
  older:SetTitle("Changed")
  EQ(older.TitleContainer.TitleText.text, "Changed", "and can change")
  UIParent = nil

  -- A client without the templates gives nothing back, so the caller can fall back.
  CreateFrame = function() return nil end
  EQ(Widgets.Button(parent, "x", 10), nil, "no button template: nil")
  EQ(Widgets.Checkbox(parent, "x"), nil, "no checkbox template: nil")
  EQ(Widgets.InputBox(parent, 10, 5), nil, "no input template: nil")
  EQ(Widgets.Window("NullgateBlacklistWindowTest3", 10, 10, "x"), nil, "no window template: nil")
  CreateFrame = savedCreate
end)

-- --- Localization: every language the game client runs in, each complete and well formed ---------------------------------

Group("All languages", function()
  local EXPECTED = { "en", "zh", "zhtw", "es", "fr", "pt", "ru", "de", "ko", "it" }

  -- The language files in the order the TOC loads them.
  local toc = assert(io.open(root .. "/NullgatesBlacklist-Forever/NullgatesBlacklist-Forever.toc", "rb"))
  local tocText = toc:read("*a")
  toc:close()
  local files = {}
  for file in tocText:gmatch("(Locale/[%w]+%.lua)") do
    if file ~= "Locale/Locale.lua" then files[#files + 1] = file end
  end
  EQ(#files, 10, "the TOC loads ten language files")

  -- Load the whole set into a table of its own, exactly as the client does.
  local all = {}
  assert(loadfile(root .. "/NullgatesBlacklist-Forever/Locale/Locale.lua"))("NullgatesBlacklist-Forever", all)
  for _, file in ipairs(files) do assert(loadfile(root .. "/NullgatesBlacklist-Forever/" .. file))("NullgatesBlacklist-Forever", all) end
  EQ(table.concat(all.Locale.Order, ","), table.concat(EXPECTED, ","), "the languages, in the order they are offered")

  local en = all.Locale.Tables.en
  local function Specifiers(text)
    local list = {}
    for spec in text:gmatch("%%[sd]") do list[#list + 1] = spec end
    return table.concat(list, " ")
  end

  for _, code in ipairs(EXPECTED) do
    local text = all.Locale.Tables[code]
    local name = all.Locale.Names[code]
    OK(type(name) == "string" and name ~= "", code .. " has a name in its own language")
    if code ~= "en" then
      local missing, wrong, blank, untranslated = {}, {}, {}, 0
      for key, english in pairs(en) do
        local own = rawget(text, key)
        if own == nil then
          missing[#missing + 1] = key
        else
          if type(own) ~= "string" or own == "" then blank[#blank + 1] = key end
          if Specifiers(english) ~= Specifiers(own) then wrong[#wrong + 1] = key end
          if own == english then untranslated = untranslated + 1 end
        end
      end
      table.sort(missing)
      table.sort(wrong)
      EQ(table.concat(missing, ","), "", code .. " translates every key")
      EQ(table.concat(wrong, ","), "", code .. " takes the same format arguments as English")
      EQ(#blank, 0, code .. " has no empty text")
      -- Names of commands, "OK" and a handful of labels can stay the same; a language
      -- where much of the text equals English was probably not translated.
      OK(untranslated < 25, code .. " is translated, not copied from English (" .. untranslated .. " identical)")
      -- Commands the player types must survive translation untouched.
      for _, command in ipairs({ "/nbl help", "/nbl check", "/nbl setup", "/nbl test", "/nbl lang", "/nbl version" }) do
        local key = ({ ["/nbl help"] = "MSG_LOADED", ["/nbl check"] = "HELP_CHECK", ["/nbl setup"] = "HELP_SETUP",
          ["/nbl test"] = "HELP_TEST", ["/nbl lang"] = "HELP_LANG", ["/nbl version"] = "HELP_VERSION" })[command]
        OK(text[key]:find(command, 1, true) ~= nil, code .. " keeps the command " .. command)
      end
      OK(text.HELP_TEST:find("<ignore|warn|notice>", 1, true) ~= nil, code .. " keeps the words of the test command")
      OK(text.ERR_CODE_FORMAT:find("BK1", 1, true) ~= nil, code .. " still names the code prefix BK1")
      OK(text.COMM_DISCLOSURE:find("\n", 1, true) ~= nil, code .. " keeps the line breaks of the notice")
      -- Valid UTF-8 throughout (Lua 5.1 has no utf8 library, so only checked where it exists).
      if utf8 then
        local bad = {}
        for key, value in pairs(text) do
          if type(value) == "string" and not utf8.len(value) then bad[#bad + 1] = key end
        end
        EQ(#bad, 0, code .. " is valid UTF-8")
      end
    end
  end

  -- The window titles of the picker can be told apart, and automatic follows the client.
  local seen = {}
  for _, code in ipairs(EXPECTED) do
    local name = all.Locale.Names[code]
    OK(not seen[name], "the language name " .. name .. " is unique")
    seen[name] = true
  end
  local saved = GetLocale
  for client, expected in pairs({ deDE = "de", frFR = "fr", esES = "es", esMX = "es", ptBR = "pt", ruRU = "ru",
    koKR = "ko", zhCN = "zh", itIT = "it", enUS = "en", enGB = "en" }) do
    GetLocale = function() return client end
    EQ(all.Locale.Resolve("auto"), expected, "a " .. client .. " client gets " .. expected)
  end
  GetLocale = function() return "zhTW" end
  EQ(all.Locale.Resolve("auto"), "zhtw", "a Traditional Chinese client gets Traditional Chinese")
  GetLocale = function() return "deDE" end
  EQ(all.Locale.Resolve("ja"), "de", "a saved language that is no longer offered follows the client")
  GetLocale = saved
  EQ(all.Locale.Resolve("ko"), "ko", "every language can be chosen by hand")

  -- A language is only as complete as its text: any gap falls back to English.
  EQ(#all.Locale.List(), 10, "the picker offers ten languages")
end)

-- --- Global channel: the envelope (section 8.10) ------------------------------------------------------------

Group("Envelope", function()
  local Envelope, Report, Const = ns.Envelope, ns.Report, ns.Const
  local message = "R1\t0123456789abcdef:7:19000:89abcdef;fedcba9876543210:1:19001:01234567"

  local scrambled = Envelope.Encode(message, 470000)
  EQ(scrambled, "pg37Xin:ggbR20ahglm;72elekH5R3;8iHb44fXjRgpmb4n8g085lkmlk483fh6:k9:Rap",
    "the scrambling of a known message for a known hour has not changed")
  EQ(#scrambled, #message, "the scrambled text is as long as the message")
  OK(not scrambled:find("[^%w:;~]"), "and uses only printable letters, digits and ':' ';' '~'")
  EQ(Envelope.Decode(scrambled, 470000), message, "it unscrambles with the same hour")
  OK(Envelope.Encode(message, 470001) ~= scrambled, "another hour scrambles it differently")
  OK(Envelope.Decode(scrambled, 470001) ~= message, "and does not unscramble with another hour")
  EQ(Envelope.Encode(message, 470000), scrambled, "the scrambling is deterministic")

  -- A report of any shape survives, with the TAB handled.
  local items = {}
  for index = 1, 6 do
    items[index] = { hash = HashOf(index), mask = 511, day = 19000 + index, token = TokenOf(index) }
  end
  local text = Report.Messages(items)[1]
  for _, hour in ipairs({ 0, 1, 470000, 999999 }) do
    EQ(Envelope.Decode(Envelope.Encode(text, hour), hour), text, "a full report round trips for hour " .. hour)
  end
  local retraction = Report.RetractMessages({ { hash = HashOf(1), token = TokenOf(1) } })[1]
  EQ(Envelope.Decode(Envelope.Encode(retraction, 5), 5), retraction, "and so does a retraction")
  OK(Envelope.Encode(text, 5):find("\t", 1, true) == nil, "the scrambled text has no TAB in it")

  -- Text that is not a report cannot be scrambled; foreign text cannot be opened.
  EQ(Envelope.Encode("hello world", 5), nil, "text with other symbols is refused")
  EQ(Envelope.Encode("R1\tabc|def", 5), nil, "a pipe is refused")
  EQ(Envelope.Decode("hello world", 5), nil, "text outside the alphabet is not opened")
  EQ(Envelope.Decode("", 5), "", "empty text is empty")
  EQ(Envelope.Encode("", 5), "", "and so is its scrambling")

  -- Only the right hour gives a readable report.
  local today = ns.Hash.Day(1700000000)
  local sample = Envelope.Encode("R1\t" .. HashOf(1) .. ":3:" .. today .. ":" .. TokenOf(1), 470000)
  local readable = 0
  for hour = 469990, 470010 do
    local plain = Envelope.Decode(sample, hour)
    if plain and Report.Parse(plain, today) then readable = readable + 1 end
  end
  EQ(readable, 1, "of twenty-one hours only the right one gives a report that parses")

  -- The hours a receiver tries.
  EQ(Envelope.Hour(3600 * 5 + 10), 5, "the hour bucket")
  EQ(Envelope.Hour(3600 * 5 - 1), 4, "the last second of an hour")
  local hours = Envelope.Hours(3600 * 5 + 10)
  EQ(hours[1] .. "," .. hours[2] .. "," .. hours[3], "5,4,6", "this hour, the one before and the one after")

  -- A different salt scrambles differently (the key is the salt plus the hour).
  local savedSalt = Const.EnvelopeSalt
  Const.EnvelopeSalt = "another salt"
  OK(Envelope.Encode(message, 470000) ~= scrambled, "a different constant gives a different scrambling")
  Const.EnvelopeSalt = savedSalt
end)

-- --- Global channel: joining and leaving --------------------------------------------------------------------

Group("Global channel", function()
  local Global, Consent, Settings, Const = ns.Global, ns.Consent, ns.Settings, ns.Const
  FreshDb()
  Global.Reset()
  local joined, joins, leaves, hides, timers, fired = false, {}, {}, {}, {}, 0
  local now = 0
  Global.io = {
    join = function(name) joins[#joins + 1] = name return true end,
    leave = function(name) leaves[#leaves + 1] = name joined = false return true end,
    id = function() return joined and 7 or nil end,
    hideFromChat = function(name) hides[#hides + 1] = name end,
    after = function(delay, fn) timers[#timers + 1] = { at = now + delay, fn = fn } end,
  }
  local function Advance(seconds)
    local limit = now + seconds
    repeat
      local pick
      for index, timer in ipairs(timers) do
        if timer.at <= limit and (not pick or timer.at < timers[pick].at) then pick = index end
      end
      if pick then
        local timer = table.remove(timers, pick)
        now = math.max(now, timer.at)
        timer.fn()
      end
    until not pick
    now = limit
  end
  ns.Events:On("COMMUNITY_CHANGED", function() fired = fired + 1 end)

  EQ(Global.name, "BlackbookGl", "the channel has a fixed name")
  EQ(Const.GLOBAL_CHANNEL, Global.name, "taken from the constants")

  -- Names from events.
  OK(Global.IsOurs("BlackbookGl"), "the bare name is ours")
  OK(Global.IsOurs("blackbookgl"), "ignoring case")
  OK(Global.IsOurs("5. BlackbookGl"), "with a channel number in front")
  OK(Global.IsOurs("12.   BlackbookGl  "), "and spaces")
  EQ(Global.IsOurs("Trade"), false, "another channel is not")
  EQ(Global.IsOurs("5. Trade - City"), false, "with its number either")
  EQ(Global.IsOurs("BlackbookGl2"), false, "a longer name is not")
  EQ(Global.IsOurs(nil), false, "nothing is not")
  issecretvalue = function(value) return value == SECRET end
  EQ(Global.IsOurs(SECRET), false, "a secret value is not")
  issecretvalue = nil

  -- Nothing is joined without consent.
  EQ(Global.Wanted(), false, "not wanted at first")
  Global.Sync()
  EQ(#joins, 0, "so nothing is joined")
  Consent.Confirm()
  Consent.SetToggle("guild", "send", true)
  EQ(Global.Wanted(), false, "other sources do not want the global channel")
  EQ(Consent.SetToggle("global", "send", true), false, "a global switch needs its own notice first")
  EQ(#joins, 0, "still nothing joined")

  -- With the notice confirmed and a switch on the channel is joined.
  Consent.ConfirmGlobal()
  OK(Consent.SetToggle("global", "receive", true), "the switch works after the notice")
  OK(Global.Wanted(), "now the channel is wanted")
  Global.Sync()
  EQ(joins[1], "BlackbookGl", "it joins the channel")
  EQ(#joins, 1, "once")
  Global.Sync()
  EQ(#joins, 1, "asking again while the join is pending does not join twice")
  local before = fired
  joined = true
  Advance(2.1)
  EQ(hides[#hides], "BlackbookGl", "once joined it is taken out of the chat windows")
  EQ(fired, before + 1, "and the rest of the addon is told it is there")
  Global.Sync()
  EQ(#joins, 1, "a joined channel is not joined again")

  -- A join that does not work is tried again a few times, then given up.
  joined = false
  joins, timers = {}, {}
  Global.Reset()
  Global.Sync()
  Advance(2.1)
  Advance(10.1)
  Advance(10.1)
  Advance(10.1)
  OK(#joins >= 2 and #joins <= 5, "a failed join is retried a few times (" .. #joins .. ")")
  Advance(100)
  local settled = #joins
  Advance(100)
  EQ(#joins, settled, "and then given up")

  -- Switching everything off leaves the channel.
  joined = true
  Consent.SetToggle("global", "receive", false)
  EQ(Global.Wanted(), false, "with both switches off it is not wanted")
  Global.Sync()
  EQ(leaves[#leaves], "BlackbookGl", "the channel is left")
  joined = false
  Global.Sync()
  EQ(#leaves, 1, "and not left twice")
  Consent.SetToggle("global", "send", true)
  OK(Global.Wanted(), "sending alone also wants it")

  -- The channel's notices stay out of the chat.
  EQ(Global.Filter(nil, "CHAT_MSG_CHANNEL_NOTICE", "YOU_JOINED", "Me", "", "7. BlackbookGl", "", 0, 0, 7, "BlackbookGl"), true,
    "the join notice of our channel is hidden")
  EQ(Global.Filter(nil, "CHAT_MSG_CHANNEL_NOTICE", "YOU_JOINED", "Me", "", "2. Trade", "", 0, 0, 2, "Trade"), false,
    "the notice of another channel is shown")
  EQ(Global.Filter(nil, "CHAT_MSG_CHANNEL_JOIN", "", "Somebody", "", "", "", 0, 0, 0, "BlackbookGl"), true,
    "someone else joining is hidden too")

  -- Registration listens for the notices and the switches.
  local savedCreate, savedTimer, savedAdd = CreateFrame, C_Timer, ChatFrame_AddMessageEventFilter
  local filters, frames = {}, {}
  CreateFrame = function()
    local frame = { events = {}, scripts = {} }
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:SetScript(name, fn) self.scripts[name] = fn end
    frames[#frames + 1] = frame
    return frame
  end
  C_Timer = { After = function() end }
  ChatFrame_AddMessageEventFilter = function(event, fn) filters[event] = fn end
  OK(Global.Register(), "registration succeeds")
  for _, event in ipairs({ "CHAT_MSG_CHANNEL_NOTICE", "CHAT_MSG_CHANNEL_NOTICE_USER", "CHAT_MSG_CHANNEL_JOIN",
    "CHAT_MSG_CHANNEL_LEAVE" }) do
    EQ(filters[event], Global.Filter, "the notice filter is installed for " .. event)
  end
  OK(frames[1] and frames[1].events.PLAYER_ENTERING_WORLD, "the join waits for the world to load")
  OK(Global.Register(), "registering twice is harmless")
  CreateFrame, C_Timer, ChatFrame_AddMessageEventFilter = savedCreate, savedTimer, savedAdd
  EQ(Global.Reset(), nil, "reset forgets what was tried")
end)

-- --- Global channel: consent of its own (section 8.10) ----------------------------------------------------------

Group("Global consent", function()
  local Consent, Settings, Const = ns.Consent, ns.Settings, ns.Const
  FreshDb()
  EQ(Consent.GlobalActive(), false, "the global notice is not confirmed at first")
  Consent.Confirm()
  EQ(Consent.GlobalActive(), false, "the general notice does not confirm the global one")
  EQ(Consent.SetToggle("global", "send", true), false, "so a global switch cannot be turned on")
  EQ(Consent.Allows("global", "send"), false, "and is not allowed")
  OK(Consent.SetToggle("guild", "send", true), "while the guild switch works")

  Settings.Set("community.global.send", true) -- as if hand edited
  EQ(Consent.Allows("global", "send"), false, "a switch set without the notice does nothing")
  Settings.Set("community.global.send", false)

  FreshDb()
  Consent.ConfirmGlobal()
  EQ(Consent.GlobalActive(), true, "confirming the global notice")
  EQ(Consent.Active(), true, "also confirms the general notice, which it repeats")
  OK(Consent.SetToggle("global", "receive", true), "a global switch now works")
  EQ(Consent.Allows("global", "receive"), true, "and is allowed")
  EQ(Consent.Allows("global", "send"), false, "independently of the other direction")
  EQ(Consent.Allows("friends", "receive"), false, "and of the other sources")
  EQ(table.concat(Consent.Receiving(), ","), "global", "it is a receiving source")

  -- Raising the global notice version switches it off until confirmed again.
  Const.GlobalConsentVersion = Const.GlobalConsentVersion + 1
  EQ(Consent.GlobalActive(), false, "a new global notice needs a new confirmation")
  EQ(Consent.Allows("global", "receive"), false, "so the switch stops working")
  OK(Consent.Allows("guild", "receive") == false, "(the guild was never on)")
  Const.GlobalConsentVersion = Const.GlobalConsentVersion - 1
  EQ(Consent.GlobalActive(), true, "and works again at the old version")

  -- Revoke withdraws both.
  Consent.Revoke()
  EQ(Consent.GlobalActive(), false, "revoking withdraws the global confirmation")
  EQ(Settings.Get("community.global.receive"), false, "and the global switches")
  EQ(Consent.Active(), false, "and the general one")
end)

-- --- Global channel: sending, receiving and passing on ------------------------------------------------------------

Group("Global sending and receiving", function()
  local Net, Global, Consent, Aggregate, Hash, Report, Envelope, Const, Resolver = ns.Net, ns.Global, ns.Consent,
    ns.Aggregate, ns.Hash, ns.Report, ns.Envelope, ns.Const, ns.Resolver
  local PREFIX = Const.COMMUNITY_PREFIX
  local SERVER = 1700000000
  local today = Hash.Day(SERVER)

  local now, timers, sent = 0, {}, {}
  local sendOk, channel, randomValue = true, 7, 5
  Net.io = {
    send = function(prefix, text, ch, target)
      if not sendOk then return false end
      sent[#sent + 1] = { prefix = prefix, text = text, channel = ch, target = target, at = now }
      return true
    end,
    after = function(delay, fn) timers[#timers + 1] = { at = now + delay, fn = fn } end,
    now = function() return now end,
    serverTime = function() return SERVER end,
    random = function() return randomValue end,
  }
  Global.io = {
    join = function() return true end, leave = function() return true end,
    id = function() return channel end,
    hideFromChat = function() end,
    after = function(delay, fn) timers[#timers + 1] = { at = now + delay, fn = fn } end,
  }
  local function Advance(seconds)
    local limit = now + seconds
    repeat
      local pick
      for index, timer in ipairs(timers) do
        if timer.at <= limit and (not pick or timer.at < timers[pick].at) then pick = index end
      end
      if pick then
        local timer = table.remove(timers, pick)
        now = math.max(now, timer.at)
        timer.fn()
      end
    until not pick
    now = limit
  end
  local function Take() local taken = sent sent = {} return taken end
  local function Me(first, last) UnitName = function(unit) if unit == "player" then return first, last end end end
  local function Fresh()
    sendOk, channel, randomValue = true, 7, 5
    Advance(100000)
    Net.Reset()
    Global.Reset()
    FreshDb()
    Me("Alice", "One")
    sent = {}
    Consent.ConfirmGlobal()
  end
  local function Open(message)  -- the report a sent global message carries
    local text = Envelope.Decode(message.text, Envelope.Hour(SERVER))
    return text and Report.Parse(text, today)
  end
  local function Wire(items) return Envelope.Encode(Report.Messages(items)[1], Envelope.Hour(SERVER)) end
  local function Item(n, mask, day) return { hash = HashOf(n), mask = mask or 1, day = day or today, token = TokenOf(n) } end
  local function Deliver(text, sender, name)
    Net.OnMessage(PREFIX, text, "CHANNEL", sender or "Carol Three", name or "BlackbookGl")
  end

  -- Sending: the record goes out enveloped, to the channel number, slowly.
  Fresh()
  Consent.SetToggle("global", "send", true)
  ns.Records.Save("Bad One", "ignore", { scam = true, toxicity = true }, "very private comment")
  Net.Sync()
  local out = Take()
  EQ(#out, 1, "one message on the global channel")
  EQ(out[1].prefix, PREFIX, "on the community prefix")
  EQ(out[1].channel, "CHANNEL", "to a channel")
  EQ(out[1].target, 7, "with the channel's number")
  OK(not out[1].text:find("\t", 1, true) and not out[1].text:find("R1", 1, true), "the text is scrambled, not a plain report")
  local report = Open(out[1])
  EQ(report.kind, "R1", "opened with the hour's key it is a report")
  EQ(report.items[1].hash, Hash.Target("bad one", Hash.Season(SERVER), "global"), "naming the target only by its global hash")
  OK(report.items[1].hash ~= Hash.Target("bad one", Hash.Season(SERVER)), "which differs from the friends and guild hash")
  OK(not out[1].text:find("Bad", 1, true) and not out[1].text:find("private", 1, true), "no name or comment on the wire")
  EQ(ns.db.community.sent.global[report.items[1].hash], report.items[1].mask, "the announcement is remembered for the global class")
  EQ(ns.db.community.sent.guild, nil, "and not for the guild")

  -- The gap on the global channel is longer than elsewhere.
  Fresh()
  Consent.SetToggle("global", "send", true)
  for index = 1, 8 do ns.Records.Save("Player" .. string.char(64 + index), "ignore", { scam = true }, "c") end
  Advance(1.1) -- the switch just went on, so the debounced sync sends the whole backlog
  Advance(10)
  local many = Take()
  EQ(#many, 2, "eight records are two messages")
  OK(many[2].at - many[1].at >= Const.Community.globalGap, "at least " .. Const.Community.globalGap .. " seconds apart")

  -- No channel, no sending: and the report is not marked as announced.
  Fresh()
  Consent.SetToggle("global", "send", true)
  channel = nil
  ns.Records.Save("Bad One", "ignore", { scam = true }, "c")
  Net.Sync()
  Advance(5)
  EQ(#Take(), 0, "nothing is sent while the channel is not joined")
  EQ(ns.db.community.sent and ns.db.community.sent.global, nil, "and nothing is marked as announced")

  -- Joining later sends the whole backlog.
  channel = 7
  Net.Changed()
  Advance(3)
  EQ(#Take(), 1, "once the channel is there the backlog goes out")

  -- A change retracts on the channel, enveloped too.
  ns.Records.Remove("Bad One")
  Net.Sync()
  Advance(5)
  local gone = Take()
  EQ(#gone, 1, "removing the record sends one message")
  EQ(Open(gone[1]).kind, "X1", "a retraction")

  -- Receiving.
  Fresh()
  Consent.SetToggle("global", "receive", true)
  local first = Wire({ Item(1, Const.LabelValue.scam) })
  Deliver(first)
  local store = ns.db.community.reports.global and ns.db.community.reports.global[HashOf(1)]
  OK(store ~= nil and store.scam[TokenOf(1)] == today, "a global report is filed under the global source")
  EQ(ns.db.community.reports.guild, nil, "not under the guild")
  EQ(ns.db.community.reports.friends, nil, "nor under friends")
  Deliver(first, "Carol Three", "5. BlackbookGl")
  Deliver(Wire({ Item(2) }), "Carol Three", "BLACKBOOKGL")
  OK(ns.db.community.reports.global[HashOf(2)] ~= nil, "the channel name may come with its number and in any case")

  local count = Aggregate.Counts()
  Deliver(Wire({ Item(3) }), "Carol Three", "Trade")
  Net.OnMessage(PREFIX, Wire({ Item(3) }), "CHANNEL", "Carol Three", nil)
  Deliver("totally not a report", "Carol Three")
  Deliver(Envelope.Encode("R1\t00:00:00:00", Envelope.Hour(SERVER)), "Carol Three")
  Deliver(Wire({ Item(3) }), "Alice One")
  Net.OnMessage(PREFIX, Wire({ Item(3) }), "SAY", "Carol Three", "BlackbookGl")
  Net.OnMessage("OTHER", Wire({ Item(3) }), "CHANNEL", "Carol Three", "BlackbookGl")
  Net.OnMessage(PREFIX, Wire({ Item(3) }), "CHANNEL", nil, "BlackbookGl")
  EQ(Aggregate.Counts(), count, "other channels, plain text, garbage, our own messages, other prefixes and no sender add nothing")

  -- The hours: this one, the one before and the one after.
  local function ForHour(n, hour) return Envelope.Encode(Report.Messages({ Item(n) })[1], hour) end
  Deliver(ForHour(10, Envelope.Hour(SERVER) - 1))
  OK(ns.db.community.reports.global[HashOf(10)], "a message from the hour before is read")
  Deliver(ForHour(11, Envelope.Hour(SERVER) + 1))
  OK(ns.db.community.reports.global[HashOf(11)], "and one from a clock that runs ahead")
  Deliver(ForHour(12, Envelope.Hour(SERVER) - 2))
  EQ(ns.db.community.reports.global[HashOf(12)], nil, "but not one from two hours ago")

  -- Not receiving: nothing is filed.
  Consent.SetToggle("global", "receive", false)
  Deliver(Wire({ Item(20) }))
  EQ(ns.db.community.reports.global[HashOf(20)], nil, "with receiving switched off nothing is filed")
  Consent.SetToggle("global", "receive", true)

  -- Retraction.
  Deliver(Envelope.Encode(Report.RetractMessages({ { hash = HashOf(1), token = TokenOf(1) } })[1], Envelope.Hour(SERVER)))
  EQ(ns.db.community.reports.global[HashOf(1)], nil, "a retraction removes the report")

  -- No sender is stored.
  local keys = {}
  local function Walk(value)
    if type(value) == "table" then for k, v in pairs(value) do keys[#keys + 1] = tostring(k) Walk(v) end
    else keys[#keys + 1] = tostring(value) end
  end
  Walk(ns.db.community.reports)
  OK(not table.concat(keys, " "):find("Carol"), "nothing in the store names the sender")

  -- Rate limits: per sender, and one ceiling for all senders together.
  Fresh()
  Consent.SetToggle("global", "receive", true)
  local oldMinute, oldCeiling = Const.Community.perMinute, Const.Community.globalPerMinute
  Const.Community.perMinute, Const.Community.globalPerMinute = 1000, 25
  local function Burst(sender, from, total)
    for index = from, from + total - 1 do Deliver(Wire({ Item(index) }), sender) end
  end
  Burst("Flood One", 100, 20)
  EQ(Aggregate.Counts(), 20, "twenty records from one sender are all taken")
  Burst("Flood Two", 200, 20)
  EQ(Aggregate.Counts(), 25, "the ceiling for all senders together stops the rest")
  Advance(61)
  Burst("Flood Two", 300, 10)
  EQ(Aggregate.Counts(), 35, "and a new minute starts afresh")
  Const.Community.globalPerMinute = oldCeiling
  Const.Community.perMinute = 30
  Burst("Flood Three", 400, 40)
  EQ(Aggregate.Counts(), 65, "a single sender is still held to its own 30 a minute")
  Const.Community.perMinute = oldMinute

  -- Tiers and rules use the global thresholds, and global data is its own world.
  Fresh()
  FreshDb()
  Me("Alice", "One")
  Consent.ConfirmGlobal()
  Consent.SetToggle("global", "receive", true)
  local key = "global flag"
  local hash = Hash.Candidates(key, SERVER, "global")[1]
  for n = 1, 4 do ns.Aggregate.Add(hash, Const.LabelValue.scam, today, TokenOf(n), "global") end
  ns.Events:Fire("COMMUNITY_CHANGED")
  EQ(Resolver.Verdict("Global Flag"), nil, "four global reporters are no flag (the global threshold is five)")
  ns.Aggregate.Add(hash, Const.LabelValue.scam, today, TokenOf(5), "global")
  ns.Events:Fire("COMMUNITY_CHANGED")
  EQ(Resolver.Verdict("Global Flag"), "notice", "five make a notice")
  local reasons = Resolver.Sources("Global Flag")
  EQ(reasons[1].from, "global", "from the global source")
  EQ(reasons[1].tier, 1, "at tier 1")
  local ok, err = ns.Rules.Add({ label = "scam", source = "global", minTier = 2, verdict = "ignore" })
  EQ(ok, false, "a global rule below tier 3 is refused")
  EQ(err, "ERR_RULE_GLOBAL", "with the reason")
  OK(ns.Rules.Add({ label = "scam", source = "global", minTier = 3, verdict = "warn" }), "at tier 3 it is accepted")
  EQ(Resolver.Verdict("Global Flag"), "notice", "and does not react to a tier 1 flag")
  for n = 6, 20 do ns.Aggregate.Add(hash, Const.LabelValue.scam, today, TokenOf(n), "global") end
  ns.Events:Fire("COMMUNITY_CHANGED")
  EQ(Resolver.Verdict("Global Flag"), "warn", "twenty reporters reach tier 3 and the rule applies")
  local lines = ns.Tooltip.Lines("Global Flag")
  local found
  for _, line in ipairs(lines) do if line.text:find(ns.L.SOURCE_GLOBAL, 1, true) then found = line.text end end
  OK(found ~= nil and found:find("20", 1, true) ~= nil, "the tooltip names the global source and the number of reporters")

  -- Passing on: once, after 5 to 60 seconds, only while sending, never twice.
  Fresh()
  Consent.SetToggle("global", "receive", true)
  Consent.SetToggle("global", "send", true)
  local delays = {}
  Net.io.random = function(low, high) delays[#delays + 1] = low .. "-" .. high return 30 end
  local wire = Wire({ Item(50, Const.LabelValue.spam) })
  Deliver(wire)
  EQ(delays[1], "5-60", "the delay is drawn from 5 to 60 seconds")
  Advance(29)
  EQ(#Take(), 0, "nothing is passed on before its delay")
  Advance(2)
  local relayed = Take()
  EQ(#relayed, 1, "after the delay the report is passed on")
  local passed = Open(relayed[1])
  EQ(passed.items[1].hash, HashOf(50), "the same target")
  EQ(passed.items[1].token, TokenOf(50), "the same anonymous token")
  EQ(passed.items[1].mask, Const.LabelValue.spam, "the same labels")
  EQ(passed.items[1].day, today, "the same day")
  EQ(relayed[1].channel, "CHANNEL", "on the global channel")
  Deliver(wire)
  Deliver(Wire({ Item(50, Const.LabelValue.spam) }), "Dave Four")
  Advance(70)
  EQ(#Take(), 0, "the same report again, even from someone else, is never passed on a second time")
  EQ(#delays, 1, "no second delay was even drawn")

  -- Reports of several reporters about one target wait side by side.
  Fresh()
  Consent.SetToggle("global", "receive", true)
  Consent.SetToggle("global", "send", true)
  Net.io.random = function() return 5 end
  Deliver(Wire({ { hash = HashOf(60), mask = 1, day = today, token = TokenOf(1) } }))
  Deliver(Wire({ { hash = HashOf(60), mask = 1, day = today, token = TokenOf(2) } }), "Dave Four")
  Advance(10)
  local both = Take()
  local tokens = {}
  for _, message in ipairs(both) do
    for _, item in ipairs(Open(message).items) do tokens[item.token] = true end
  end
  OK(tokens[TokenOf(1)] and tokens[TokenOf(2)], "two reporters' reports about one target are both passed on")

  -- No passing on without sending, without a channel, or when the queue is full.
  Fresh()
  Consent.SetToggle("global", "receive", true)
  Deliver(Wire({ Item(70) }))
  Advance(70)
  EQ(#Take(), 0, "a client that only receives passes nothing on")
  Consent.SetToggle("global", "send", true)
  Deliver(Wire({ Item(70) }))
  Advance(70)
  EQ(#Take(), 0, "and a report it already saw stays unpassed even when sending is switched on later")
  channel = nil
  Deliver(Wire({ Item(71) }))
  channel = 7
  Advance(70)
  EQ(#Take(), 0, "a client that has not joined the channel passes nothing on")
  local oldCap = Const.Community.relayQueueCap
  Const.Community.relayQueueCap = 2
  sendOk = false
  for n = 80, 90 do Deliver(Wire({ Item(n) }), "Sender" .. string.char(65 + n % 20) .. " One") end
  Advance(6)
  EQ(Net.PendingCount(), 2, "a full queue stops more reports from being passed on")
  Const.Community.relayQueueCap = oldCap
  sendOk = true

  -- Revoking withdraws what was reported on the global channel as well.
  Fresh()
  Consent.SetToggle("global", "send", true)
  ns.Records.Save("Bad One", "ignore", { scam = true }, "c")
  Net.Sync()
  Advance(5)
  Take()
  Consent.Revoke()
  Advance(5)
  local withdrawn = Take()
  EQ(#withdrawn, 1, "revoking sends one retraction to the global channel")
  EQ(Open(withdrawn[1]).kind, "X1", "which is a retraction")
  EQ(Consent.GlobalActive(), false, "and the global notice has to be confirmed again")
  UnitName = nil
end)

-- --- Test mode: sample tooltips (section 6.6) ---------------------------------------------------------------------

Group("Tooltip test mode", function()
  local Tooltip = ns.Tooltip
  local function Contains(text, needle, label)
    OK(type(text) == "string" and text:find(needle, 1, true) ~= nil, label .. ": " .. tostring(text) .. " lacks " .. tostring(needle))
  end
  FreshDb()
  Tooltip.SetTestMode(false)
  EQ(Tooltip.TestMode(), false, "test mode is off at first")
  Tooltip.SetTestMode(true)
  EQ(Tooltip.TestMode(), true, "it can be turned on")
  Tooltip.SetTestMode(false)
  EQ(Tooltip.TestMode(), false, "and off")
  EQ(Tooltip.SampleCount, 6, "there are six sample situations")

  local function Texts(lines)
    local list = {}
    for _, line in ipairs(lines) do list[#list + 1] = line.text end
    return table.concat(list, "\n")
  end

  -- Each sample looks like the real thing, and says it is a sample.
  for index = 1, Tooltip.SampleCount do
    local lines = Tooltip.SampleLinesAt(index)
    OK(#lines >= 3, "sample " .. index .. " has a verdict, reasons and the sample line")
    Contains(lines[1].text, "Nullgate's Blacklist: ", "sample " .. index .. " starts with the verdict like a real tooltip")
    EQ(lines[#lines].text, ns.L.TT_TEST_BANNER, "sample " .. index .. " ends by saying it is sample data")
  end
  local ignore = Texts(Tooltip.SampleLinesAt(1))
  Contains(ignore, ns.L.VERDICT_IGNORE, "the first sample is an ignore")
  Contains(ignore, ns.L.LABEL_HARASSMENT, "with its reasons")
  Contains(ignore, ns.L.SAMPLE_COMMENT_IGNORE, "and a comment")
  Contains(Texts(Tooltip.SampleLinesAt(2)), ns.L.VERDICT_WARN, "the second is a warning")
  local fromList = Texts(Tooltip.SampleLinesAt(3))
  Contains(fromList, ns.L.SAMPLE_LIST_NAME, "the third comes from an imported list")
  Contains(fromList, ns.L.SAMPLE_AUTHOR, "by someone")
  local guild = Texts(Tooltip.SampleLinesAt(4))
  Contains(guild, ns.L.SOURCE_GUILD, "the fourth is a guild flag")
  Contains(guild, ns.L.TIER_2, "at tier 2")
  local both = Texts(Tooltip.SampleLinesAt(5))
  Contains(both, ns.L.SOURCE_GUILD, "the fifth shows the guild")
  Contains(both, ns.L.SOURCE_FRIENDS, "and friends on lines of their own")
  local global = Texts(Tooltip.SampleLinesAt(6))
  Contains(global, ns.L.SOURCE_GLOBAL, "the sixth is a global flag")
  Contains(global, ns.L.TIER_3, "at tier 3")

  -- A player always gets the same sample; different players see different ones.
  local seen, distinct = {}, 0
  for _, name in ipairs({ "Aaa Bbb", "Ccc Ddd", "Eee Fff", "Ggg Hhh", "Iii Jjj", "Kkk Lll", "Mmm Nnn", "Ooo Ppp",
    "Qqq Rrr", "Sss Ttt", "Uuu Vvv", "Www Xxx", "Yyy Zzz", "Abc Def", "Ghi Jkl", "Mno Pqr" }) do
    local first, second = Texts(Tooltip.SampleLines(name)), Texts(Tooltip.SampleLines(name))
    EQ(first, second, name .. " always gets the same sample")
    EQ(Texts(Tooltip.SampleLines(string.upper(name))), first, "whatever the case")
    if not seen[first] then seen[first] = true distinct = distinct + 1 end
  end
  OK(distinct >= 4, "different players get different samples (" .. distinct .. " of 6 among sixteen)")

  -- Sample texts are not mixed up with a real record of the same name.
  ns.Records.Save("Aaa Bbb", "ignore", { spam = true }, "a real comment")
  OK(not Texts(Tooltip.SampleLines("Aaa Bbb")):find("a real comment", 1, true), "a real record does not leak into a sample")
  ns.Records.Remove("Aaa Bbb")
end)

-- --- Summary -------------------------------------------------------------------

io.write(string.format("%d checks, %d failure(s)\n", checks, failures))
io.stdout:flush()
if failures > 0 then os.exit(1) end
os.exit(0)
