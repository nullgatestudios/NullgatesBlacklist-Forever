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
  EQ(ButtonTexts(root), L.CTX_IGNORE .. "|" .. L.CTX_WARN, "new player: ignore and warn")

  root = StubRoot()
  EQ(ContextMenu.Build(root, { name = "Chat Guy-Realm" }), true, "a chat name gets entries")
  EQ(ButtonTexts(root), L.CTX_IGNORE .. "|" .. L.CTX_WARN, "name context works like a unit")

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
  EQ(ButtonTexts(root), L.CTX_EDIT .. "|" .. L.CTX_REMOVE, "known player: edit and remove")
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
  EQ(ButtonTexts(root), L.CTX_IGNORE .. "|" .. L.CTX_WARN .. "|" .. L.CTX_ADOPT, "list-only player: adopt is offered")
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

-- --- Summary -------------------------------------------------------------------

io.write(string.format("%d checks, %d failure(s)\n", checks, failures))
io.stdout:flush()
if failures > 0 then os.exit(1) end
os.exit(0)
