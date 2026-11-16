# Blackbook addon: design document

Status: v1 draft for implementation. The addon is named **Blackbook**; every fixed name lives in `Core/Const.lua`. A rename touches that file and the addon folder and TOC file names, nothing else (the packaging script reads the name from the TOC).

Audience: the implementing developer (an AI coding model). Reviewer: Claude. Read sections 0 to 3 before writing any code.

---

## 0. Rules for the implementer

1. **Clean-room.** Build only from this document. Do not look at, copy from, or imitate any reference addon (Peacekeeper, OpenMap or others). Use the names, field names, message formats and file layout given here. Do not invent compatibility with other addons' formats.
2. **Small, reviewable steps.** Deliver one milestone (section 12) at a time. Each delivery lists the files changed, how to test, and anything you were unsure about. Do not start the next milestone before the review of the previous one.
3. **Do not guess at WoW APIs.** Section 2 lists the APIs this design assumes exist in the target client. If you are unsure an API exists or how it behaves, say so in the delivery notes. Never silently invent API names. Guard optional APIs with `if X then`.
4. **No dependencies.** No Ace3, no LibStub, no embedded libraries. Plain Lua 5.1 and the WoW API only.
5. **Simplest complete solution.** No speculative features, no config for fixed values, no abstractions with one implementation. Exceptions are the two seams this document asks for (the codec/transport split and the aggregate store), because later milestones depend on them.
6. **Never skip validation at trust boundaries.** Everything that arrives from another player (addon messages, pasted codes, imported lists) is untrusted. Section 8.6 defines the checks.
7. **Secret values.** Some values returned by the client can be "secret" and must not be compared, concatenated, or used as table keys. Wrap every value that comes from the game's chat or unit APIs with the `Safe` helpers from section 4.
8. **Pure logic stays testable.** Modules marked *pure* in section 4 must not touch frames or other WoW globals at load time, so they can be tested with plain `lua5.1` (section 11).
9. **Versioning and packaging.** Every delivery follows section 15: version bump where required, changelog entries, and a zip built with `tools/package.ps1`.

---

## 1. Goals and non-goals

### Goals
- An account-wide personal blocklist. Each record has a verdict (`ignore` or `warn`), one or more labels, a required comment, timestamps and who added it.
- Enforcement for `ignore`: hide chat, auto-decline invites, duels and trades, optional notices, optional auto-reply.
- Marking for `warn` and for flagged players from outside sources: chat icon, target portrait overlay, tooltip lines.
- Sharing lists: copy/paste codes and in-game transfer, with per-label rules that decide how a received list affects you.
- **Opt-in community reports** (milestone M8 and later): anonymized label reports shared with friends and guild members, with tiered escalation and per-label enforcement rules. A global in-game channel follows in M9.
- English and German.

### Non-goals (v1)
- Any server, website, or external service. The aggregator in section 8.9 is planned, not built.
- Sharing free-text comments through community reports.
- Automatic enforcement from community data unless the player created an explicit rule.
- Compatibility with any other addon's code format.

---

## 2. Client and API assumptions

Target client: `## Interface: 16001`. Player names are **two-part names** ("First Last") with the realm suffix dropped, and are unique across servers. Verify the following before relying on them, and report any that are missing:

| Area | APIs assumed |
|---|---|
| Secrets | `issecretvalue(v)` (may be `nil` in older clients: treat as "not secret") |
| Names | `UnitName(unit)` returning first and last name separately, `GetNormalizedRealmName`, `GetRealmName`, `strtrim`, `strsplit` |
| Chat filtering | `ChatFrame_AddMessageEventFilter` or `ChatFrameUtil.AddMessageEventFilter` |
| Invites and requests | events `PARTY_INVITE_REQUEST`, `GUILD_INVITE_REQUEST`, `DUEL_REQUESTED`, `TRADE_SHOW`; calls `DeclineGroup`, `DeclineGuild`, `CancelDuel`, `CancelTrade`, `StaticPopup_Hide` |
| Addon messages | `C_ChatInfo.RegisterAddonMessagePrefix`, `C_ChatInfo.SendAddonMessage` (channels `GUILD`, `WHISPER`, and a custom channel in M9), event `CHAT_MSG_ADDON` |
| Battle.net | `BNSendGameData`, event `BN_CHAT_MSG_ADDON`, `C_BattleNet.GetFriendAccountInfo`, `C_BattleNet.GetGameAccountInfoByID`, `BNGetNumFriends` |
| Friends and guild | `C_FriendList.GetNumFriends`, `C_FriendList.GetFriendInfoByIndex`, `GetNumGuildMembers`, `GetGuildRosterInfo`, events `FRIENDLIST_UPDATE`, `GUILD_ROSTER_UPDATE`, `BN_FRIEND_INFO_CHANGED`, `BN_FRIEND_ACCOUNT_ONLINE`, `BN_FRIEND_ACCOUNT_OFFLINE` |
| Menus | `Menu.ModifyMenu(tag, fn)` with root description methods `CreateDivider`, `CreateTitle`, `CreateButton` |
| Tooltip | `TooltipDataProcessor.AddTooltipPostCall` with `Enum.TooltipDataType.Unit` |
| UI | plain `Frame`, `Button`, `CheckButton` and `EditBox` frames drawn with textures and font strings (no Blizzard frame templates), `CreateFont`, `WowStyle1DropdownTemplate` (`DropdownButton`), `WowScrollBoxList`, `MinimalScrollBar`, `CreateScrollBoxListLinearView`, `ScrollUtil.InitScrollBoxListWithScrollBar`, `CreateDataProvider`, `StaticPopupDialogs` |
| Encoding | `C_EncodingUtil.CompressString` / `DecompressString` (optional; the portable code must work without them) |
| Time and timers | `time`, `GetServerTime`, `GetTime`, `C_Timer.After`, `C_Timer.NewTicker` |
| Metadata | `C_AddOns.GetAddOnMetadata(name, field)`, fallback to the global `GetAddOnMetadata` (used only to show the TOC version) |

Fallback policy: if a UI template or the menu API is missing, the addon must still load and the slash commands must still work. It prints one notice and disables only the missing feature.

---

## 3. Vocabulary (use these names)

| Term | Meaning |
|---|---|
| **record** | One player in the user's own list |
| **verdict** | Effective result for a player: `ignore`, `warn`, `notice` (rank 3, 2, 1) |
| **label** | A fixed reason identifier (section 5.1) |
| **subscription** | An imported list received from another player |
| **community** | Reports received through the M8/M9 sharing system |
| **source** | Where community data came from: `friends`, `guild`, later `global` |
| **tier** | Escalation level 1 to 4 of a community flag (section 8.3) |
| **rule** | A user-created mapping from subscription label or community label to a verdict |
| **target key** | Lowercased normalized name, used as the table key |
| **target hash** | 16-hex-digit anonymous hash of a target key (section 8.2) |

---

## 4. Architecture

One shared namespace table `ns` is passed to every file as `local _, ns = ...`. Modules attach themselves as `ns.<Module>`. A tiny internal event bus lets modules react to data changes without direct calls into UI code.

### 4.1 Repository layout and files

Only the addon folder ships. Tests, tools, the changelog and build output stay outside it.

```
<repository root>/
  Blackbook/            -- the addon folder (name must equal the TOC file name)
  tests/                -- run.lua, smoke.lua (section 11)
  tools/package.ps1     -- packaging script (section 15)
  assets/icon.svg       -- source of the addon icon; Blackbook/icon.tga is its 128x128 32-bit TGA render
  zips/                 -- build output, git-ignored
  CHANGELOG.md          -- section 15.2
  DESIGN.md
  .gitignore            -- contains zips/
```

The reference addon folders next to this file are not part of the repository and must not be read, copied or shipped.

Files inside `Blackbook/` (load order = TOC order):

```
Blackbook.toc
Locale/Locale.lua      -- language registry and the immediate switch (loads first)
Locale/enUS.lua ... Locale/ukUA.lua   -- the fifteen languages, one file each (section 10)
Core/Const.lua         -- names, prefixes, limits, label table, tier tables (pure)
Core/Events.lua        -- ns.Events:On(name, fn), :Fire(name, ...) (pure)
Core/Safe.lua          -- secret-value guards (see below)
Core/Output.lua        -- ns.Output.Text / Escape / Print shared by all modules
Core/Identity.lua      -- name parsing, same-player check
Core/Settings.lua      -- defaults, schema migrations, accessors
Data/Records.lua       -- own list CRUD
Data/Subscriptions.lua -- imported lists and their label rules
Data/Resolver.lua      -- verdict computation with cache (pure given store)
Data/Query.lua         -- filter and sort of record arrays for the list tab (pure)
Share/Wire.lua         -- escaping and line format helpers (pure)
Share/Codec.lua        -- list code encode/decode and validation (pure)
Community/Hash.lua     -- hashing, token derivation, season (pure)
Community/Report.lua   -- builds report batches from own records, wire format and its parser (pure)
Community/Aggregate.lua-- store per source, tiers, expiry, caps (pure given ns.db)
Community/Consent.lua  -- opt-in state, per-source switches, revoke and purge
Community/Rules.lua    -- rules, the community verdict, hidden flags
Community/Roster.lua   -- character friends and who is online (Battle.net friends are not read yet)
Community/Net.lua      -- outbox, background sync, receiving and its checks
Community/Global.lua   -- M9 only: channel, envelope cipher, relay
Enforce/Chat.lua       -- one chat filter pipeline
Enforce/Requests.lua   -- invite, duel, trade
Enforce/Reply.lua      -- auto-reply policy
Display/Markers.lua    -- how each verdict looks; chat icon helper (loads before Enforce/Chat.lua)
Display/Portrait.lua
Display/Tooltip.lua
UI/Theme.lua           -- colours, fonts and drawing helpers of the addon's look (loads before Widgets)
UI/Widgets.lua
UI/Editor.lua          -- add/edit dialog
UI/Manager.lua         -- main window frame and tab bar; tabs register with Manager.RegisterTab
UI/TabList.lua         -- "My list" tab
UI/TabImported.lua     -- "Imported" tab
UI/TabLists.lua        -- "Lists" tab (rules per imported list)
UI/TabShare.lua        -- "Share" tab (export and import codes)
UI/TabCommunity.lua    -- "Community" tab (consent, switches, preview, revoke)
UI/TabRules.lua        -- "Rules" tab (community rules, hidden flags)
UI/TabSettings.lua     -- "Settings" tab
UI/Wizard.lua           -- first-run wizard
UI/ReplyControl.lua    -- auto-reply choice and preview, shared by the wizard and the Settings tab
Diagnostics/Check.lua  -- "/bb check": client feature report and the loopback test
UI/Minimap.lua
UI/ContextMenu.lua
Main.lua               -- ADDON_LOADED bootstrap, slash commands, events
```

### 4.2 `Safe` helpers
`Safe.IsSecret(v)` returns false when `issecretvalue` is absent. `Safe.Str(v)` returns `v` only if it is a non-secret string, else `nil`. All code that reads chat authors, message text, unit names or roster values passes them through `Safe` first.

### 4.3 Events
Names used on the bus: `RECORDS_CHANGED`, `SUBSCRIPTIONS_CHANGED`, `COMMUNITY_CHANGED`, `SETTINGS_CHANGED`. The Resolver clears its cache on any of them. UI modules refresh on them. Nothing in `Data/` or `Community/` calls a UI function directly.

---

## 5. Data model

Saved variable: `BlackbookDB` (account-wide). One schema version number `db.version` with ordered migration functions in `Settings.lua` (no inline version checks elsewhere).

### 5.1 Labels (fixed order; never renumber, never rename IDs)

| Bit | ID | Meaning |
|---|---|---|
| 1 | `harassment` | Insults or targeted harassment |
| 2 | `hate` | Hate speech |
| 3 | `toxicity` | General toxic behavior |
| 4 | `griefing` | Griefing or sabotage |
| 5 | `ninja_loot` | Loot stealing |
| 6 | `scam` | Scams |
| 7 | `spam` | Spam or advertising |
| 8 | `private_dispute` | Personal dispute (excluded from community sharing by default) |
| 9 | `other` | Other (excluded from community sharing by default) |

A label set is stored as a table `{ [id] = true }` and transmitted as an integer bitmask (bit n set means label n). Provide `Const.LabelsToMask(set)` and `Const.MaskToLabels(mask)`.

### 5.2 `BlackbookDB`

```lua
{
  version = 1,
  settings = { ... },          -- section 5.3
  records = {                  -- own list; key = target key
    ["first last"] = {
      name = "First Last",     -- display form
      verdict = "ignore",      -- "ignore" | "warn"
      labels = { toxicity = true },
      comment = "text",        -- required, 1..255 chars
      created = 1700000000,    -- time()
      updated = 1700000000,
      addedBy = "First Last",  -- the user's own character
    },
  },
  subscriptions = {            -- imported lists; key = list id
    ["a1b2c3d4e5f6"] = {
      id = "a1b2c3d4e5f6", name = "List name", author = "First Last",
      exported = 1700000000, imported = 1700000500,
      records = { ["first last"] = { name=, labels=, comment=, created=, verdictHint= } },
      rules = { toxicity = "warn", scam = "ignore" },  -- label -> verdict; missing = "notice"
    },
  },
  community = {                -- section 8.4
    install = { secret = "<32 hex>" },        -- made at first start, never sent
    reports = { friends = {}, guild = {}, global = {} },  -- per source: [hash][label][token] = day
    sent = { guild = { [hash] = mask }, friends = { ... } },  -- what was announced, so only changes are sent
    hidden = { ["<target hash>"] = "First Last" },  -- local "this flag is wrong", name kept to undo it
    tokenCount = 0, targetCount = { guild = 0 },      -- counters for the caps
  },
}
```

### 5.3 Settings (defaults)

| Key | Default | Meaning |
|---|---|---|
| `language` | `"auto"` | `auto`, `en`, `de` |
| `hideChat` | `true` | hide chat from ignored players |
| `autoDecline` | `true` | decline invites, duels, trades from ignored players |
| `showNotices` | `true` | print notices about blocked actions |
| `showMinimap` | `true` | minimap button |
| `minimapAngle` | `220` | degrees |
| `replyMode` | `"none"` | `none`, `short`, `labels` |
| `setupDone` | `false` | wizard finished |
| `export.id` | random 12 hex | stable list ID for this user's exports |
| `export.name` | `nil` | list name; default built from the player's first name |
| `export.labels` | all `true` | which labels to include when exporting |
| `export.comments` | `true` | include comments |
| `community.friends.send` | `false` | send reports to friends |
| `community.friends.receive` | `false` | accept reports from friends |
| `community.guild.send` | `false` | send reports to guild |
| `community.guild.receive` | `false` | accept reports from guild |
| `community.global.send` / `.receive` | `false` | M9 |
| `community.shareLabels` | all `true` except `private_dispute`, `other` | labels that may be reported |
| `community.consentVersion` | `0` | disclosure version the user confirmed |
| `community.rules` | `{}` | list of community rules (section 8.5) |

---

## 6. Core behavior (M1 to M5)

### 6.1 Identity (`Core/Identity.lua`)
- `Identity.Normalize(text)`: trim, strip a trailing `-Realm` suffix (the part after the last hyphen), collapse internal whitespace, return `nil` for empty or non-string or secret input.
- `Identity.FromUnit(unit)`: join first and last name from `UnitName`, then normalize. Return `nil` if any part is secret.
- `Identity.Key(name)`: lowercase of the normalized name.
- `Identity.Same(a, b)`: true if both normalize and their keys are equal. Used for addon-message senders, whose names may arrive with or without a realm suffix and with different spellings.
- `Identity.Self()`: the player's own normalized name, `"?"` if unavailable.

### 6.2 Records (`Data/Records.lua`)
`Get(name)`, `Save(name, verdict, labels, comment)`, `Remove(name)`, `All()` (array, sorted by name). A record requires **at least one label and a non-empty trimmed comment (max 255 characters, counted per UTF-8 character with `Identity.CharCount`)**. `Records.Check` reports the first problem without saving, so the editor and `Save` share one set of rules. `Save` copies the label set. Each mutation fires `RECORDS_CHANGED`.

### 6.3 Resolver (`Data/Resolver.lua`)
`Resolver.Verdict(name)` returns `verdict, reasons` where `verdict` is `"ignore"`, `"warn"`, `"notice"` or `nil`, and `reasons` is an array describing the sources.

Algorithm, evaluated in this order:
1. If the player has an own record, return its verdict. Own records always win and no other source is consulted.
2. If the target's community flag is locally hidden (section 8.7), skip community sources.
3. Otherwise take the **strongest** verdict among:
   - each subscription that lists the player: the strongest of `rules[label]` over the entry's labels, defaulting to `notice`;
   - community rules (section 8.5) that match;
   - community data with no matching rule: `notice` if the flag reached tier 1.
4. Rank: `ignore` > `warn` > `notice`.

The Resolver keeps a cache keyed by target key and clears it on any bus event listed in 4.3. It also exposes `Resolver.Sources(name)` returning the detailed reason list used by tooltips and the manager.

### 6.4 Enforcement
All enforcement reads `Resolver.Verdict`.

**Chat (`Enforce/Chat.lua`):** register one filter function per chat event (say, yell, emote, text emote, channel, whisper, party and leader, raid and leader and warning, instance and leader, guild, officer). The filter runs ordered stages:
1. If `hideChat` and the verdict is `ignore`: hide the message. For whispers, print at most one notice per person per 60 seconds (the filter is called once per chat window, so the throttle is required).
2. Otherwise, for `warn` or `notice`: return the message with an icon prefix (section 6.6).
3. Always return unchanged for secret author or text.

**Requests (`Enforce/Requests.lua`):** if `autoDecline` and the verdict is `ignore`, decline the party invite, guild invite, duel and trade, hide the matching popup, and print a notice if `showNotices`. For trades, read the other party through `Identity.FromUnit("npc")`.

**Auto-reply (`Enforce/Reply.lua`):** when a whisper arrives from a player whose verdict comes from an **own record** with `ignore`, and `replyMode ~= "none"`:
- at most once per session per player;
- sent after a 1.5 second delay, in the user's language;
- `short`: a fixed polite sentence; `labels`: a sentence listing label names, truncated to 250 bytes without cutting a UTF-8 character;
- **never contains the comment**;
- the user's own outgoing reply is hidden from their chat for 15 seconds (match by text prefix);
- send failures are caught with `pcall` and reported once.
- Implementation: a frame listens to `CHAT_MSG_WHISPER` (an event, so it also fires for a whisper the chat filter hides); the echo of the reply is hidden by a filter on `CHAT_MSG_WHISPER_INFORM` that matches the first 40 bytes of the text for 15 seconds. The text is cut with a UTF-8 safe truncation (`Wire.Truncate`). The comment is not even passed to the reply code, so it cannot leak.

### 6.5 Slash commands
`/blackbook` and `/bb`:
`(none)` toggle manager, `list`, `ignore <name>`, `warn <name>`, `remove <name>`, `setup` (opens the wizard), `test <ignore|warn|notice>` (a sample chat line with that verdict's icon), `check` (client feature report and a loopback test of the sharing connection), `minimap`, `lang de|en|auto`, `version` (prints the TOC version), `help`. The `ignore` and `warn` commands open the editor with the name prefilled.

### 6.6 Display
- Chat icon prefix for `warn` (alert icon) and `notice` (blue arrow); `ignore` is hidden by chat enforcement, so it needs no icon except in the manager and tooltip (red cross); when `hideChat` is off, the ignored player's messages carry the red cross instead.
- Portrait overlay on the target frame: diagonal strike for `ignore`, corner icon for `warn` and `notice`. Update on `PLAYER_TARGET_CHANGED` and on bus changes. Look up the portrait defensively (the frame layout varies).
- Tooltip lines for player units: verdict with icon, labels, comment (escape `|` as `||`), plus the sources for subscriptions (max three) and, for community data, the tier, the count and the sources (section 8.8).

---

## 7. Sharing lists (M6)

### 7.1 Portable list code
Layout: `BK1:<body>:<crc>`.
- `payload` = text produced by `Wire` (7.2).
- If `C_EncodingUtil.CompressString` exists and compression shrinks the payload, set `mode = "C"`, else `"R"`. The prefix becomes `BK1C:` or `BK1R:`.
- `body` = Base64 (standard alphabet, `=` padding) of the (possibly compressed) payload. Implement Base64 yourself in `Wire.lua`; it must work without WoW.
- `crc` = 8 hex digits of a checksum of the **uncompressed payload**. Use Adler-32 (two 16-bit halves formatted separately so the number never overflows when formatted).
- Decoding strips all whitespace first, because codes get line-wrapped by chat tools.
- Compression is only used when `C_EncodingUtil` has both calls, the result is smaller **and** decompresses back to the same payload (every call is guarded with `pcall`). A `BK1C` code needs the client's decompression to be read; without it the error names that.
- Size limits (`Const.Limits`): a pasted code of at most 5,400,000 characters and a decoded payload of at most 4,000,000 bytes, so a hostile code cannot allocate without bound. Both are checked before the work that would exhaust them.
- Error keys: `ERR_CODE_EMPTY`, `_TOO_BIG`, `_FORMAT`, `_VERSION`, `_BASE64`, `_NOCOMPRESS`, `_CORRUPT`, `_CHECKSUM`, `_HEADER`, `_TOO_MANY`, `_RECORD` (with the line number).

### 7.2 Payload text format
Line oriented, fields separated by a TAB, with `\t`, `\n`, `\\` escaped as `\t`, `\n`, `\\` in field values.

```
H <TAB> 1 <TAB> <listId> <TAB> <listName> <TAB> <author> <TAB> <exportedAt>
R <TAB> <name> <TAB> <verdictHint> <TAB> <labelMask> <TAB> <created> <TAB> <comment>
R ...
```
`verdictHint` is `ignore`, `warn` or empty and is informational only.

### 7.3 Validation on import (all must hold, otherwise reject)
- Header present and version `1`; `listId` is 1 to 32 characters `[0-9a-f]`.
- Counts: at most 5000 records. Name at most 60, comment at most 255, list name and author at most 60.
- Each record name passes `Identity.Normalize`; label mask is an integer between 1 and 511; times are numbers or empty.
- Unknown label bits are dropped, not rejected.
- A list whose ID equals the user's own export ID is rejected as "your own list".
- A record name containing a control character or a pipe is rejected (it could not be a player name and could inject chat markup); control characters in the list name, author and comments become spaces.
- The player's own character is dropped from an imported list, so a list can never hide the player's own chat.
- At most 50 imported lists are kept; replacing an existing one is always allowed.
- The import dialog shows list name, author, record count and date. Existing subscriptions with the same ID are replaced, **keeping the user's rules**.

### 7.4 In-game transfer: removed
Version 0.6.0 had a popup-based "send my list" between two players. It was removed in 0.7.0: sharing with friends and guild is now automatic and silent (section 8), and the list code (7.1 to 7.3) remains for moving a list between accounts or sharing it outside the game. The prefix `BKX` is no longer used.

---

## 8. Community reports (M8 and M9)

### 8.1 Design principles
- **Opt-in, per source.** Everything is off by default. Sending and receiving are separate toggles for each source. The player confirms the disclosure once; after that sharing is **automatic and silent**: no popups, no prompts and no chat output while reports are sent or received.
- **Sources are kept apart.** Friends, guild and (later) global have separate switches, separate stores, separate tier evaluation and separate rules. Data of one source never counts towards another, and there is no "any source" rule.
- **Anonymized, not anonymous.** Reports contain no reporter data. For Friends and Guild, a direct recipient can still tell which character sent a message. The consent text must say so.
- **Informational by default.** Community data produces at most a `notice` unless the user creates a rule.
- **Nothing identifying is stored.** Receivers never store the message sender.

### 8.2 Hashing and tokens (`Community/Hash.lua`, pure)
No 64-bit integers exist in Lua 5.1, so build 64 bits from two independent 32-bit hashes.

- `Hash.Target(targetKey, seasonId)` returns 16 lowercase hex digits: two 32-bit FNV-1a hashes with different offset bases over `seasonSalt .. targetKey`. `seasonSalt` is a constant string in `Const.lua` combined with `seasonId`.
- `Hash.Season(serverTime)` returns `floor(serverTime / (90 * 86400))`.
- `Hash.Day(serverTime)` returns `floor(serverTime / 86400)`.
- `Hash.Token(installSecret, targetHash)` returns 8 hex digits from a 32-bit FNV-1a over `installSecret .. targetHash`. It is stable per install and target, unlinkable across targets.
- Lookups try the current and previous season, to cover the boundary.

**Be honest in all user-facing text:** the hash stops casual browsing, but anyone can hash a list of known names. It is not encryption.

### 8.3 Tiers (constants in `Const.lua`)

A flag's tier is the highest tier whose condition holds, counting **distinct tokens** whose report day lies within the window ending today.

| Tier | Friends and guild | Global (M9) |
|---|---|---|
| 1 Flag | 3 in 90 days | 5 in 90 days |
| 2 Elevated | 7 in 30 days | 12 in 30 days |
| 3 Urgent | 10 in 7 days | 20 in 7 days |
| 4 Critical | 15 in 1 day | 30 in 1 day |

The global numbers are proposals for review; keep them in one table so they are easy to change.

### 8.4 Aggregate store (`Community/Aggregate.lua`, pure)
Structure inside `db.community.reports`:

```lua
reports[source][targetHash][labelId][token] = day   -- day = Hash.Day at report time
```

- `Aggregate.Add(targetHash, mask, day, token, source)`: for every label bit set, store the token for that source if absent (the first-seen day wins; later duplicates are ignored). Enforce the caps below.
- `Aggregate.Retract(targetHash, token, source)`: remove that token for the target **in that source only**. A retraction is only as trustworthy as the knowledge of the token, so one source can never delete another source's reports.
- `Aggregate.Tier(targetHash, labelId, sources, today)` returns the tier and the distinct count. Friends and guild may be combined (a reporter who told both counts once); friends or guild together with global is refused (tier 0), because those worlds are kept apart.
- `Aggregate.Summary(targetHash, sources, today)` gives the best tier, the distinct reporters over all labels and each label's tier, or nil below tier 1.
- `Aggregate.Expire(today)`: drop tokens older than 90 days and empty tables. Run at login and once per day while online.
- Caps: 20000 targets per source (new targets are refused at the cap), 50 tokens per target and label (oldest dropped first), 200000 entries in total (the oldest 5% are dropped when it is full). Counters are kept in the saved data and rebuilt once if missing.
- `Aggregate.Purge()` empties the store (used on revoke).

### 8.5 Community rules (`Community/Rules.lua`, pure)
```lua
rule = { label = "scam", source = "friends"|"guild"|"global", minTier = 2, verdict = "warn"|"ignore" }
```
- A rule matches a target when the tier of that label **in that one source** is at least `minTier`. Each source is evaluated on its own and yields its own reason; a rule for one source never reacts to another source's data.
- Rules for a source the user has not enabled for receiving never match.
- Defaults when the user creates a rule: `minTier = 2`. A `global` rule cannot have a `minTier` below 3 (enforce in the editor and again in the matcher).
- Creating a rule with verdict `ignore` shows a confirmation: "This will hide chat and decline requests from matching players automatically."
- The strongest verdict across all matching rules wins.

### 8.6 Wire protocol (Friends and Guild)

Prefix `BKC` (its own prefix, because the game throttles bursts per prefix).

Message body (at most 255 bytes):
```
R1 <TAB> rec;rec;rec...
```
Each `rec` is `<hash16>:<mask3>:<day>:<token8>` where `mask` is a decimal label bitmask (1 to 511), `day` a decimal day number. At most 6 records per message.

Retraction: `X1 <TAB> <hash16>:<token8>` (at most 6, `;`-separated).

Hello handshake (to find friends who use the addon): `H1` and the reply `H2`. A friend who comes online gets an `H1` (only when sending to friends is on). The receiver answers `H2` **only when receiving from friends is on** (so a player who does not take part does not reveal that they run the addon), at most once a minute per friend. An `H2` is accepted only from a friend and only when sending to friends is on; it marks them as an addon user, and only confirmed, online addon users receive reports. A confirmed friend who comes back online gets the whole list again.

**Receiving checks (all of them; drop silently on any failure):**
1. The prefix matches. Text and sender are non-secret strings.
2. The channel is `GUILD`, `WHISPER`, or a Battle.net game-data message. Ignore any other channel.
3. The sender is not the player (use `Identity.Same` and the player's GUID where the client provides it).
4. The source is enabled for receiving: `guild` messages need `community.guild.receive`; whispers and Battle.net need `community.friends.receive` **and** the sender must be a confirmed friend.
5. Battle.net senders are accepted only if they play this game and are of the player's **faction**. Character whispers cannot cross factions anyway. *Battle.net messaging is not implemented yet; only the guild channel and character whispers are used.*
6. Each record: hash is 16 lowercase hex; mask is 1 to 511 after clamping to known bits; day is within the last 90 days and not in the future by more than 1 day; token is 8 hex.
7. Per-sender rate cap: at most 30 records per minute and 600 per hour; extra records are dropped.
8. If a sender cannot be matched to a roster entry unambiguously, drop the message.

The sender is used for these checks only and is **never stored**.

### 8.7 Sending (`Community/Net.lua`, `Community/Report.lua`)
- **What gets reported:** the user's own records with `verdict = "ignore"` only (not `warn`), restricted to labels in `community.shareLabels`. A record with no shareable label is skipped.
- A report batch is built by `Report.Build(records, now)`: for each record compute `hash`, `mask` (shareable labels only), `day` (the record's created day; clamped to the last 90 days), `token`.
- **When (sync model):** `db.community.sent[class]` remembers what was announced to a class of destinations (`guild`, `friends`) as `hash -> mask`. After any change (records, settings, community state, batched for one second) `Net.Sync` compares the current reports with it and sends only the difference: new or changed targets as `R1`, removed ones as `X1`. A target whose labels changed is retracted first, then reported again. Switching a send switch on clears that class's memory, so the whole backlog goes out. A report dropped after its retries is forgotten, so the next sync sends it again. A friend who answers `H2`, or who comes back online, gets the whole current list.
- **Retract:** when a record is removed, turned into a warn, or loses all shareable labels, an `X1` goes out. Revoking consent sends retractions for everything announced to the classes that are still switched on, then stops; the receivers' copies of old reports expire after 90 days regardless.
- **Destinations:** `GUILD` (when the player is in a guild and guild sending is on); character whispers to each confirmed addon-user friend who is online and has friends sending on.
- **Outbox:** one message at a time, a 0.5 s gap. Items wait in one slot per destination and target: a newer report for the same target replaces an unsent one, and a retraction cancels an unsent report. Up to 6 items of one kind share a message. Every send is wrapped in `pcall`; a failed send is retried after 5 seconds, up to 3 attempts in all. Destinations take turns.
- **Roster (`Community/Roster.lua`):** track who is online in the guild, character friends and Battle.net friends (same game only). Rescan, debounced by 1 second, on the roster and friend events listed in section 2. Request fresh rosters every 30 seconds only while the manager window is open.

### 8.8 Local "this is wrong" and display
- `db.community.hidden[hash] = "First Last"` (this season's and the previous season's hash) hides community data and cancels community enforcement for that target. The name is kept on this install only, so the Rules tab can list it and undo it. Never shared. The context menu offers *This flag is wrong* for players flagged by community data.
- Tooltip: one line per source, `<Source>: <N> players reported this player (<tier name>)`, followed by the labels, so friends and guild stay visibly apart. Chat and portrait markers use the `notice` look (or the verdict a rule gives). *A stronger look at tier 3 and above is not done yet.*

### 8.9 Consent
- Show a **disclosure screen** (wizard page and settings tab) before any community toggle can be turned on. It must state, in plain language:
  1. What is sent: a hash of the player's name, label identifiers, a day number, an anonymous token; never comments, never your name.
  2. That the hash only prevents casual browsing.
  3. For Friends and Guild: that people receiving a report can see which of your characters sent it.
  4. That receiving enables community data to affect markers, and rules to affect enforcement, but only if you create the rule.
  5. That sharing can be switched off at any time, and that "Revoke and delete" stops sending and wipes all received community data.
- The disclosure has a version number. `community.consentVersion` must equal the current version for any toggle to take effect. If the disclosure text changes, bump the version, which forces a new confirmation and turns the toggles off until then.
- A **preview** button shows the next batch that would be sent (labels and hashed values) before sending anything.

### 8.10 Global channel (M9)
Added only after Friends and Guild are reviewed and working.

- **Channel:** one fixed hidden custom channel with a constant name. The channel is joined only when `global.send` or `global.receive` is on, and left when both are off.
- **Envelope:** the whole message body is transformed with a keystream derived from `hourBucket = floor(GetServerTime() / 3600)` and a constant string. Use a simple keyed stream (for example an LCG or xorshift seeded from a 32-bit hash of those inputs). The envelope is **obfuscation, not secrecy**: the key comes from public addon code and the hour, so a modified client can read everything. It limits casual harvesting and old logs, and makes reports from different hours unlinkable on the wire.
- Receivers try the current and the previous hour, to cover clock skew and the hour boundary.
- **Relay once:** a client that receives a valid, unseen report re-sends it after a random delay of 5 to 60 seconds, then remembers the token so it never relays it twice (a hop limit of one; no loops). A relay message carries exactly the same record format. The receiver never stores the original sender, and a relayed report cannot be tied to its origin.
- **Rules:** use the `global` thresholds from 8.3; `global` rules require `minTier` of 3 or more; separate consent screen text stating that the global channel is public to all addon users and that anonymity here is limited to the data itself.
- **Rate limits:** the same caps as 8.6, plus a global ceiling on messages per minute across all senders; silent drop above it.
- **Aggregator seam:** `Report.Build` produces transport-agnostic batches, and `Aggregate.Add` accepts a `source` argument. A future aggregator is just another input with `source = "global"`. Nothing further is built for it now.

---

## 9. User interface

### The look
Every window uses one flat, dark style, defined in `UI/Theme.lua` and built by `Widgets` so that no tab draws its own chrome:
- A near-black panel with a 1 pixel border; a title bar with a 2 pixel gold line on top (the gold comes from the addon icon) and a close button; calm grey text, white for what matters, gold for headings.
- **Buttons** are flat fills that lighten on hover and darken when pressed. `primary` (gold, dark text) is for the one main action of a window (Save, Next, Confirm, Add rule, Create code, Import), `danger` (red text) for destructive ones (Revoke, Remove list), `ghost` for the close button. A disabled button looks switched off and ignores clicks.
- **Checkboxes** are a small dark box that fills with the accent colour when ticked; the label is part of the click area. **Input boxes** are dark fields whose border turns gold while they have the cursor. **Tabs** are plain text with a gold line under the active one.
- Only plain textures and font strings are used, so no template can be missing. Fonts are the addon's own font objects (`CreateFont`), so no other addon's text changes: the sans-serif face of the chat for Latin and Cyrillic, and the client's standard font for Chinese, Japanese and Korean, which need its glyphs. Where `CreateFont` is missing the Blizzard fonts are used.
- Lists keep the client's thin scroll bar and dropdown menus (`WowStyle1DropdownTemplate`), which already look modern.

Keep the layout simple and uniform; use `Widgets.lua` helpers (checkbox, radio group, labelled field) instead of repeating frame code.

- **Editor dialog** (opened from commands, the manager and the context menu): player name, verdict (`ignore` or `warn`), a multi-select dropdown for labels (with a checkbox fallback if the dropdown template is missing), a required comment (max 255), Save and Cancel. Save is disabled until at least one label and a non-empty comment exist. Pressing Escape closes it.
- **Manager window** with tabs:
  1. *My list*: search box, verdict filter, label filter, sortable columns (name, verdict, labels, comment, date), scroll list with row tooltip, add-player box, delete with Shift-click.
  2. *Imported*: all subscription records, with the effective verdict per row; click to adopt into your own list.
  3. *Lists*: choose a subscription, set the verdict per label (`notice`, `warn`, `ignore`), remove the list (Shift-click).
  4. *Share*: export (list name, label selection, comments checkbox, Create code button with a read-only code box), import (paste box, Import and Clear buttons, a confirmation popup showing list name, author, size and date),  The code and paste boxes sit in a scroll frame (`Widgets.CodeBox`), because a long code in a plain multi-line box would draw over the widgets below it and steal their clicks. The export settings are saved as they are changed; typing is never overwritten by a refresh.
  5. *Community*: the disclosure and its confirm button, send and receive switches for friends and guild (global shown as not available), the reasons that may be shared, a preview of what would be sent (hashes and labels, never names), a counter of held reports and queued messages, and *Revoke and delete* (with a confirmation).
  6. *Rules*: the community rules (add one rule per chosen reason; Shift-click removes; a rule that ignores asks for confirmation) and the list of hidden flags (click to show again).
  7. *Settings*: language, enforcement toggles (including the minimap button), the auto-reply choice (off, short, with reasons) with a preview of the sentence, and *Run setup again*.
- **Wizard** (first run, 4 pages, `setupDone`): welcome and language; what "ignore" does (with the hide-chat and decline switches); auto-reply; finish and minimap. It opens two seconds after login on the first run only. Closing it in any way (Finish, the close button, Escape) counts as done, but only after it has really been shown, so merely building the window cannot finish the setup. `/bb setup` and a button on the Settings tab open it again. It never switches sharing on or confirms the community notice. A separate page for community consent is reachable from the Community tab, not forced on first run.
- **Minimap button:** left-click toggles the manager, drag repositions, tooltip shows the record count.
- **Context menu:** add entries on player menus (unit frames, chat names, group, guild lists): *Ignore...*, *Warn...* when no record exists; *Edit...* and *Remove* when one does; *Adopt...* when only a subscription lists the player; and for a community-flagged player, *This flag is wrong*. Do nothing for the player's own character or for non-players.

---

## 10. Localization

- Strings live in `Locale/enUS.lua` and `Locale/deDE.lua` as keys of a table `ns.L`. Missing German keys fall back to English via a metatable. Write all strings and keys yourself; do not reuse wording from other addons.
- Each language file registers itself with `Locale.Register(code, ownName, table)`; every language falls back to English per key through a metatable. `language = "auto"` follows `GetLocale()` (client locale to code), and a choice that is not registered falls back to English.
- **A language change takes effect at once, with no `/reload`.** `Locale.Set(choice)` saves the choice, swaps `ns.L` and runs the registered hooks; the main window, the editor and the wizard throw their frames away and are rebuilt in the new language (the wizard reopens on the same page and the window on the same tab). Frames are rebuilt rather than relabelled because a text-to-key lookup is ambiguous (two keys can share one translation). A rebuilt window gets a new global name (`Widgets.FrameName`). Anything typed but not saved in a rebuilt window is lost, which is acceptable for a rare action.
- The language pickers (Settings tab, wizard) are one `Widgets.Choice`: a dropdown with radio entries, or a grid of checkboxes if the client has no dropdown. They list *Automatic* and then every registered language under its own name, so adding a language needs no UI change.
- Characters outside the client's fonts cannot be shown. Latin, Cyrillic and Chinese/Japanese/Korean render on current clients; Arabic, Hindi, Bengali and Urdu scripts do not.
- **The fifteen languages**, in the order the picker lists them: English, Chinese (Simplified), Spanish, French, Portuguese, Russian, Indonesian, German, Japanese, Turkish, Vietnamese, Korean, Italian, Polish and Ukrainian. They are the world's most spoken languages that the client can display; Hindi, Arabic, Bengali, Urdu and Marathi would rank higher than some of these but have no glyphs in any WoW font (and Arabic and Urdu need right-to-left text), so they are left out. Chinese, Japanese and Korean use the client's standard font; the others use the addon's sans-serif font.
- **Machine translation.** Apart from English and German, every language file is machine-translated and has not been reviewed by a native speaker; its header says so. A native speaker can improve a language by editing that one file. A test checks each language for completeness (every key), identical format arguments (`%s`, `%d`), kept command words (`/bb ...`), unchanged `BK1`, valid UTF-8, and that it was not simply copied from English.
- A language with no WoW locale of its own (Indonesian, Turkish, Vietnamese, Polish, Ukrainian) is never chosen by "automatic"; the player picks it by hand.
- Format strings use `%s` and `%d`. Escape `|` as `||` whenever user text is placed into chat or tooltips.

---

## 11. Testing

Beyond the groups below, `tests/run.lua` also keeps the locales honest: every English key has a German text and the reverse, both take the same `%s` and `%d` arguments, and every locale key the code asks for exists. Saved data of every age (empty, unversioned, partial, damaged, newer) must come out whole, with nothing the player chose lost.

Pure modules must be testable outside the game. Provide `tests/run.lua` in the repository root. It loads each addon file with `loadfile(path)("Blackbook", ns)` so the `local _, ns = ...` header works, stubs the few WoW globals needed (`time`, `strtrim`, `strsplit`) and runs assertions with plain `lua5.1`. Required tests:

- **Identity:** normalization cases (realm suffix, extra spaces, empty), `Same`.
- **Wire and Codec:** Base64 round trip for lengths 0 to 10, escape round trip, encode/decode round trip, checksum failure, truncated input, oversized input, bad header, unknown label bits.
- **Resolver:** own record wins; strongest of several subscriptions; rules mapping; cache invalidation; community flag hidden.
- **Hash:** determinism, known value check for the FNV implementation, different outputs for different seasons, tokens differ per target.
- **Aggregate:** distinct-token counting, first-seen day wins, retract, expiry, caps, tier thresholds at the boundaries (2 versus 3 reporters, day 89 versus 90), de-duplication across sources.
- **Rules:** minTier, source scoping, the global minimum of 3, strongest verdict.
- **Net validation:** a table-driven test over malformed records and messages (bad hex, oversize, negative or future day, unknown channel, own sender, disabled source).

`tests/smoke.lua` is an optional companion: it loads the files listed in the TOC with stubbed WoW globals, fires `ADDON_LOADED` and drives the slash commands, so a wrong TOC name, slash key, saved variable or frame name fails on the command line instead of in game. Run it from the repository root with `lua tests/smoke.lua`.

For in-game behavior, each milestone ends with a manual test script listed in section 12.

---

## 12. Milestones and acceptance

Each milestone must load without Lua errors, work with `/reload`, and leave previous milestones working. Each delivery also carries its version, changelog entries and zip (section 15.5).

**M1: foundation.** `Blackbook.toc`, `Const`, `Events`, `Safe`, `Identity`, `Settings` (with migration framework), `Records`, `Main` with slash commands, `Locale`, plus `CHANGELOG.md`, `.gitignore` and `tools/package.ps1` (section 15). *Accept:* `/bb ignore First Last`, `/bb list`, `/bb remove` work from chat commands (editor can be a temporary stub that requires labels and a comment); data survives `/reload`; Identity tests pass; `tools/package.ps1` builds `zips/Blackbook-0.1.0.zip` and passes its own checks.

**M2: resolver and enforcement.** `Resolver`, `Enforce/Chat`, `Enforce/Requests`. *Accept:* an ignored player's chat is hidden; a whisper notice appears at most once per minute per player; invites, duels and trades are declined; toggles take effect without reload; Resolver tests pass.

**M3: editor and context menu.** `UI/Widgets`, `UI/Editor`, `UI/ContextMenu`. *Accept:* the editor validates as in section 9; right-click menus show the correct entries; the fallback checkboxes appear when the dropdown template is unavailable.

**M4: manager and minimap.** `UI/Manager` "My list" and "Settings" tabs, `UI/Minimap`. *Accept:* search, filter, sort and delete work; scroll position is retained on refresh; the minimap button drags and persists.

**M5: display.** `Display/*`, chat markers. *Accept:* chat icons for `warn`; portrait overlay for each verdict; tooltip content including escaping of `|`.

**M6: sharing lists (0.6.0).** `Wire`, `Codec`, `Subscriptions`, manager tabs *Imported*, *Lists*, *Share*. *Accept:* export then import the code on a second account or after clearing; checksum errors report clearly; rules change the effective verdict; codec tests pass.

**M7: community, friends and guild (0.7.0, built before the polish step).** `Hash`, `Report`, `Aggregate`, `Consent`, `Rules`, `Roster`, `Net`, the *Community* and *Rules* tabs, resolver, tooltip and menu integration. Sharing is automatic and silent after one confirmed disclosure; friends and guild are separate from each other's switches and from the global world. *Accept:* nothing is sent or accepted while consent is missing; each switch works independently; a record change is reported in the background without any prompt and a removal is retracted; reports from the guild or from a friend flag players with a notice only; a rule can raise that per source and tier; hidden flags suppress it; revoke withdraws and deletes; all validation and tier-boundary tests pass.

**M8: polish (0.8.0).** `Enforce/Reply` (with its control and preview line on the Settings tab), `UI/Wizard`, German locale completion (checked by test), settings migration tests, and `/bb check` so the sharing connection can be tested with one character. *Accept:* auto-reply obeys every rule in 6.4; first-run wizard appears once; the language switch works.

**M9: global channel.** `Community/Global.lua` and its consent text. *Accept:* the hour-boundary overlap works; relays do not loop; global rules enforce the tier 3 minimum; rate limits drop floods.

---

## 13. Review protocol

For each delivery, the reviewer checks:
1. The delivery follows the rules in section 0 (no copied reference code, no dependencies, no guessed APIs).
2. Every trust boundary in section 8.6 and 7.3 is implemented and tested.
3. Secret-value handling is applied to every external string.
4. No module calls UI code from data modules; the bus is used.
5. No per-frame work while windows are closed; timers hide themselves when idle.
6. Saved-variable changes go through a numbered migration.
7. Tests exist for the pure modules touched and pass.
8. Strings exist in both languages and escape `|`.
9. The TOC version follows the rules in 15.1, `CHANGELOG.md` has matching player-facing entries, and the TOC is the only place the version is written.
10. `tools/package.ps1` was run, its output is attached, and the zip has the expected name and layout (15.4).

---

## 14. Open items and risks

- **Legal and policy review** (Blizzard addon policy, privacy rules for character names) before any release of M8 or M9. This design reduces exposure but does not remove it.
- **Brigading.** Small friend and guild groups can reach tier 1 with three people. That is why rules default to tier 2 or higher and nothing enforces without an explicit rule.
- **Global thresholds** in 8.3 are untested proposals.
- **Aggregator hosting** (who runs it, how data reaches players) is undecided; it is planned for after M9.
- **API availability** (section 2) must be confirmed against the actual client before M8; Battle.net messaging in particular.
- **Whisper targets with a space.** Hello and reports to friends are whispered to a two-part name ("First Last"). If the client refuses such a target, sending to friends silently fails (guild sharing is unaffected). Confirm in game.
- **Battle.net friends** are not read yet, so a friend who is only a Battle.net friend (not a character friend) is not reached.
- **Guild broadcast reaches everyone in the guild who runs the addon**, including members who never agreed to anything; they only receive hashes and tokens, and only store them if they opted in to receiving from the guild.
- **Retraction trust.** Anyone who has seen a token can retract it from the source it came from. The effect is limited to that source and to one report.
- **`C_EncodingUtil` signatures** are assumed (`CompressString(text)` returning a string, `DecompressString(text)`); the code verifies the round trip and falls back to the raw code, but a client where compression works differently simply never produces `BK1C` codes.
- **Vietnamese** needs stacked diacritics; if the addon's sans-serif font lacks them, those letters will not display and the player should choose another language until the font is changed.
- **Scroll frame template.** `UIPanelScrollFrameTemplate` is assumed for the code boxes; without it they fall back to a single-line edit box.

---

## 15. Versioning, changelog and packaging

### 15.1 Semantic versioning

- Format `MAJOR.MINOR.PATCH`: digits only, no leading zeros, no pre-release or build suffix (so zip names stay simple).
- **Single source of truth:** the `## Version:` line in `Blackbook/Blackbook.toc`. Never write the version anywhere else in code, locale files or tests. At runtime, read it with the metadata API from section 2 (`/bb version`).
- Bump rules:

| Change | Bump |
|---|---|
| Bug fix, text or translation fix, internal cleanup with no behavior change | PATCH |
| New feature or setting, new UI, new label, a database schema migration, a wire format addition that old clients ignore | MINOR |
| Removing or changing a feature, setting or command in a way players notice; a wire or list-code format change that old clients cannot read | MAJOR (after 1.0.0; before 1.0.0 use MINOR) |

- **Milestone mapping:** M1 ships as `0.1.0`, M2 as `0.2.0`, and so on up to M9 as `0.9.0`. A review round that only fixes problems in a delivered milestone is a PATCH (`0.2.1`, `0.2.2`). `1.0.0` is set only by the project owner for the first public release, after the legal and policy review in section 14.
- A schema migration (section 5) must be listed in the changelog under *Changed*, naming the old and new `db.version`.
- A format change (`BK1` to `BK2`, `R1` to `R2`) must keep reading the old format, and the changelog says so.
- **Released versions are immutable.** If a zip with a version number has gone to anyone, fix problems in a new version. Never rebuild the same version with different contents.

### 15.2 Changelog

- File: `CHANGELOG.md` in the repository root. Format: Keep a Changelog 1.1.0, newest first.
- The top section is always `## [Unreleased]`. Released sections are `## [0.1.0] - 2026-11-20` (ISO date).
- Subsections, only those used: `### Added`, `### Changed`, `### Deprecated`, `### Removed`, `### Fixed`, `### Security`.
- Entries are one line each, written for **players** (what they can now do or what was fixed), not file names or internal refactors. Internal-only changes need no entry.
- The changelog entry goes into the same delivery as the code it describes, under `[Unreleased]`.
- Template:

```markdown
# Changelog

All notable changes to Blackbook are listed here. The format follows Keep a Changelog and the project uses Semantic Versioning.

## [Unreleased]

## [0.1.0] - 2026-11-20
### Added
- Personal blocklist with `/bb ignore`, `/bb warn`, `/bb remove` and `/bb list`.
```

### 15.3 Release procedure (every delivery)

1. Decide the new version with 15.1 and set `## Version:` in the TOC.
2. In `CHANGELOG.md`, rename `[Unreleased]` to `[<version>] - <today>` and add a fresh empty `[Unreleased]` above it.
3. Run the tests (`lua tests/run.lua`).
4. Run `tools/package.ps1`. It must finish without errors.
5. Include in the delivery notes: the new version, the changelog entries, and the script's output (path, file count, size, SHA-256).

Do not tag, publish or upload anything. The project owner does that.

### 15.4 Packaging script: `tools/package.ps1`

Requirements:
- Runs on Windows PowerShell 5.1 (the Windows default) and on PowerShell 7. It needs no tools other than optionally `lua`. It works from any current directory by locating the repository root from `$PSScriptRoot`.
- Invocation: `powershell -ExecutionPolicy Bypass -File tools/package.ps1`, with optional `-Force` (overwrite an existing zip) and `-SkipTests`.
- **Do not use `Compress-Archive`.** In Windows PowerShell 5.1 it writes backslashes into zip entry names, which breaks extraction on other platforms and some tools. Use `System.IO.Compression` (`Add-Type -AssemblyName System.IO.Compression.FileSystem`) and set every entry name explicitly with forward slashes.
- The script never modifies source files, including the version and the changelog.
- On any failure it prints one clear message, exits non-zero and leaves no partial zip behind (write to a temporary file in `zips/`, rename on success).

Steps, in order:
1. Find the addon folder `Blackbook/` and its TOC `Blackbook/Blackbook.toc`. The addon name is the TOC file name without the extension and must equal the folder name.
2. Read `## Version:` from the TOC and check it matches the semver pattern in 15.1.
3. Check the TOC also has `## Interface:` and `## Title:`.
4. Check `CHANGELOG.md` has a heading `## [<version>] - YYYY-MM-DD` with at least one entry under it. If `## [Unreleased]` still has entries, print a warning.
5. Check the TOC file list: every listed file exists, with the exact letter case used on disk, and every `.lua` file inside the addon folder is listed. If the TOC has `## IconTexture:`, the file it names must exist inside the addon folder. Report each mismatch by name.
6. Unless `-SkipTests`: run `lua tests/run.lua`, and `lua tests/smoke.lua` if it exists. A non-zero exit aborts the build. If `lua` is not found, print a warning and continue.
7. Build `zips/<Addon>-<version>.zip` (for example `zips/Blackbook-0.1.0.zip`). Create `zips/` if missing. Refuse to overwrite an existing file unless `-Force`. Contents:
   - one top-level folder `Blackbook/` holding the addon folder's files with their relative paths, plus `CHANGELOG.md` copied to `Blackbook/CHANGELOG.md`;
   - sorted by path, compression `Optimal`;
   - excluded: hidden files and folders (names starting with `.`), `*.bak`, `*.tmp`, `Thumbs.db`, `.DS_Store`.
8. Verify the finished zip by reopening it: every entry starts with `Blackbook/`, no entry name contains a backslash, `Blackbook/Blackbook.toc` is present, the TOC version inside the zip equals the version read in step 2, and the entry count matches the number of files collected.
9. Print the zip path, version, file count, size in bytes and SHA-256.

### 15.5 What each milestone delivery includes

The code and tests for the milestone, the TOC version from the 15.1 mapping, the `CHANGELOG.md` entries, the zip built by the script, and the script output pasted into the delivery notes. Section 13 lists the matching review checks.
