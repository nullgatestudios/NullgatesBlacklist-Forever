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
| UI | `BasicFrameTemplateWithInset`, `UIPanelButtonTemplate`, `UICheckButtonTemplate`, `InputBoxTemplate`, `WowStyle1DropdownTemplate` (`DropdownButton`), `WowScrollBoxList`, `MinimalScrollBar`, `CreateScrollBoxListLinearView`, `ScrollUtil.InitScrollBoxListWithScrollBar`, `CreateDataProvider`, `StaticPopupDialogs` |
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
Locale/enUS.lua
Locale/deDE.lua
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
Share/Transfer.lua     -- in-game list transfer sessions
Community/Hash.lua     -- hashing, token derivation, season (pure)
Community/Report.lua   -- builds report batches from own records (pure)
Community/Aggregate.lua-- store, tiers, expiry, caps (pure)
Community/Rules.lua    -- community rule matching (pure)
Community/Consent.lua  -- opt-in state, disclosure, revoke and purge
Community/Roster.lua   -- who is online: guild, friends, Battle.net friends
Community/Net.lua      -- outbox, send, receive, validation
Community/Global.lua   -- M9 only: channel, envelope cipher, relay
Enforce/Chat.lua       -- one chat filter pipeline
Enforce/Requests.lua   -- invite, duel, trade
Enforce/Reply.lua      -- auto-reply policy
Display/Markers.lua    -- how each verdict looks; chat icon helper (loads before Enforce/Chat.lua)
Display/Portrait.lua
Display/Tooltip.lua
UI/Widgets.lua
UI/Editor.lua          -- add/edit dialog
UI/Manager.lua         -- main window frame and tab bar; tabs register with Manager.RegisterTab
UI/TabList.lua         -- "My list" tab
UI/TabSettings.lua     -- "Settings" tab
UI/Wizard.lua
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
    install = { secret = "<32 hex>" },
    reports = { ... },
    hidden = { ["<target hash>"] = true },   -- local "this flag is wrong"
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

### 6.5 Slash commands
`/blackbook` and `/bb`:
`(none)` toggle manager, `list`, `ignore <name>`, `warn <name>`, `remove <name>`, `setup`, `minimap`, `lang de|en|auto`, `version` (prints the TOC version), `help`. The `ignore` and `warn` commands open the editor with the name prefilled.

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
- The import dialog shows list name, author, record count and date. Existing subscriptions with the same ID are replaced, **keeping the user's rules**.

### 7.4 In-game transfer (`Share/Transfer.lua`)
Prefix `BKX`. Fields are TAB separated; the first field is a word.

| Message | Fields | Meaning |
|---|---|---|
| `OFFER` | sessionId, partCount, recordCount, listName | sender proposes a transfer |
| `ACCEPT` | sessionId | receiver agrees |
| `DECLINE` | sessionId | receiver declines or is busy |
| `PART` | sessionId, index, chunk | one chunk of the list code |

- Chunk size 200 bytes; at most 600 parts.
- Sent via `WHISPER` only, queued at one message per 0.3 s. A failed send retries up to 20 times, then drops the session and reports failure once.
- The offer times out after 60 s. The receiver's popup times out slightly sooner.
- Per-sender session state machine: `OFFERED -> ACCEPTED -> RECEIVING -> DONE|FAILED`. A new offer while a popup is open is auto-declined. Receivers ignore offers from players whose verdict is `ignore`.
- Each part is accepted only for an active session, from the matching sender (`Identity.Same`), with an unseen index in range. When all parts have arrived, run the normal import validation, skipping the confirmation (the receiver already agreed).
- A receiver session expires after 5 minutes.

---

## 8. Community reports (M8 and M9)

### 8.1 Design principles
- **Opt-in, per source.** Everything is off by default. Sending and receiving are separate toggles for each source.
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
reports[targetHash][labelId][source][token] = day   -- day = Hash.Day at report time
```

- `Aggregate.Add(targetHash, mask, day, token, source)`: for every label bit set, store the token for that source if absent (the first-seen day wins; later duplicates are ignored). Enforce the caps below.
- `Aggregate.Retract(targetHash, token)`: remove that token everywhere for the target.
- `Aggregate.Tier(targetHash, labelId, enabledSources, today)` returns the tier and the distinct count, de-duplicating tokens across the enabled sources.
- `Aggregate.Expire(today)`: drop tokens older than 90 days and empty tables. Run at login and once per day while online.
- Caps: 20000 targets, 50 tokens per target per label per source (oldest dropped first), 200000 tokens in total (oldest dropped first).
- `Aggregate.Purge()` empties the store (used on revoke).

### 8.5 Community rules (`Community/Rules.lua`, pure)
```lua
rule = { label = "scam", source = "guild"|"friends"|"global"|"any", minTier = 2, verdict = "warn"|"ignore" }
```
- A rule matches a target when the aggregate tier for `(label, sources)` is at least `minTier`. `source = "any"` means the union of the sources the user currently has enabled for receiving.
- Rules for a source the user has not enabled for receiving never match.
- Defaults when the user creates a rule: `minTier = 2`. A `global` rule cannot have a `minTier` below 3 (enforce in the editor and again in the matcher).
- Creating a rule with verdict `ignore` shows a confirmation: "This will hide chat and decline requests from matching players automatically."
- The strongest verdict across all matching rules wins.

### 8.6 Wire protocol (Friends and Guild)

Prefix `BKC` (separate from `BKX`, because the game throttles bursts per prefix).

Message body (at most 255 bytes):
```
R1 <TAB> rec;rec;rec...
```
Each `rec` is `<hash16>:<mask3>:<day>:<token8>` where `mask` is a decimal label bitmask (1 to 511), `day` a decimal day number. At most 6 records per message.

Retraction: `X1 <TAB> <hash16>:<token8>` (at most 6, `;`-separated).

Hello handshake (to find friends who use the addon): `H1` and the reply `H2`. A friend who comes online gets an `H1`. A reply of `H2` marks them as an addon user; only confirmed addon users receive reports.

**Receiving checks (all of them; drop silently on any failure):**
1. The prefix matches. Text and sender are non-secret strings.
2. The channel is `GUILD`, `WHISPER`, or a Battle.net game-data message. Ignore any other channel.
3. The sender is not the player (use `Identity.Same` and the player's GUID where the client provides it).
4. The source is enabled for receiving: `guild` messages need `community.guild.receive`; whispers and Battle.net need `community.friends.receive` **and** the sender must be a confirmed friend.
5. Battle.net senders are accepted only if they play this game and are of the player's **faction**. Character whispers cannot cross factions anyway.
6. Each record: hash is 16 lowercase hex; mask is 1 to 511 after clamping to known bits; day is within the last 90 days and not in the future by more than 1 day; token is 8 hex.
7. Per-sender rate cap: at most 30 records per minute and 600 per hour; extra records are dropped.
8. If a sender cannot be matched to a roster entry unambiguously, drop the message.

The sender is used for these checks only and is **never stored**.

### 8.7 Sending (`Community/Net.lua`, `Community/Report.lua`)
- **What gets reported:** the user's own records with `verdict = "ignore"` only (not `warn`), restricted to labels in `community.shareLabels`. A record with no shareable label is skipped.
- A report batch is built by `Report.Build(records, now)`: for each record compute `hash`, `mask` (shareable labels only), `day` (the record's created day; clamped to the last 90 days), `token`.
- **When:** when a record is saved with shareable labels (queue one report per source), when the user enables a send toggle (send the whole backlog, throttled), and when a friend replies `H2` (send the backlog to that friend only). Do not resend a report that was already sent to that destination during this session (remember sent `hash:token` pairs in memory only).
- **Retract:** when a record is removed or loses all shareable labels, send an `X1` for it. When consent is revoked, send retractions for everything previously reported if the connection allows; at minimum stop sending.
- **Destinations:** `GUILD` (if the player is in a guild and `guild.send`); for each confirmed addon-user friend that is online: a Battle.net message if the friend is reachable that way, otherwise a character whisper. Skip a friend who is already covered by the guild broadcast.
- **Outbox:** one message at a time, a 0.5 s gap, one pending slot per `(destination, key)` where a newer report for the same target replaces an unsent one. The sender frame hides itself when the queue is empty. Wrap every send in `pcall`; a failed send is retried after a delay, up to 3 times.
- **Roster (`Community/Roster.lua`):** track who is online in the guild, character friends and Battle.net friends (same game only). Rescan, debounced by 1 second, on the roster and friend events listed in section 2. Request fresh rosters every 30 seconds only while the manager window is open.

### 8.8 Local "this is wrong" and display
- `db.community.hidden[hash] = true` hides community data and cancels community enforcement for that target. Never shared. The context menu offers it for flagged players; the manager can undo it.
- Tooltip line: `Reported by <N> players (<source list>) for: <labels>` plus the tier name. Chat and portrait markers use the `notice` look, with a stronger look at tier 3 and above.

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

Keep the layout simple and uniform; use `Widgets.lua` helpers (checkbox, radio group, labelled field) instead of repeating frame code.

- **Editor dialog** (opened from commands, the manager and the context menu): player name, verdict (`ignore` or `warn`), a multi-select dropdown for labels (with a checkbox fallback if the dropdown template is missing), a required comment (max 255), Save and Cancel. Save is disabled until at least one label and a non-empty comment exist. Pressing Escape closes it.
- **Manager window** with tabs:
  1. *My list*: search box, verdict filter, label filter, sortable columns (name, verdict, labels, comment, date), scroll list with row tooltip, add-player box, delete with Shift-click.
  2. *Imported*: all subscription records, with the effective verdict per row; click to adopt into your own list.
  3. *Lists*: choose a subscription, set the verdict per label (`notice`, `warn`, `ignore`), remove the list (Shift-click).
  4. *Share*: export (list name, label selection, comments checkbox, Export button with a read-only code box), import (paste box, Import and Clear buttons), send to player (name box and button).
  5. *Community*: consent, per-source toggles, share labels, rule editor, backlog preview, hidden flags, revoke and delete.
  6. *Settings*: language, enforcement toggles, auto-reply mode with a preview line, minimap, restart wizard.
- **Wizard** (first run, 4 pages): welcome and language; what "ignore" does; auto-reply; finish and minimap. A separate page for community consent is reachable from the Community tab, not forced on first run.
- **Minimap button:** left-click toggles the manager, drag repositions, tooltip shows the record count.
- **Context menu:** add entries on player menus (unit frames, chat names, group, guild lists): *Ignore...*, *Warn...* when no record exists; *Edit...* and *Remove* when one does; *Adopt...* when only a subscription lists the player; *Send my list*; and for a community-flagged player, *This flag is wrong*. Do nothing for the player's own character or for non-players.

---

## 10. Localization

- Strings live in `Locale/enUS.lua` and `Locale/deDE.lua` as keys of a table `ns.L`. Missing German keys fall back to English via a metatable. Write all strings and keys yourself; do not reuse wording from other addons.
- `language = "auto"` follows `GetLocale()`. Changing the language shows a "type /reload" notice.
- Format strings use `%s` and `%d`. Escape `|` as `||` whenever user text is placed into chat or tooltips.

---

## 11. Testing

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

**M6: sharing lists.** `Wire`, `Codec`, `Subscriptions`, `Transfer`, manager tabs *Imported*, *Lists*, *Share*. *Accept:* export then import the code on a second account or after clearing; checksum errors report clearly; rules change the effective verdict; in-game transfer works with accept and decline, timeouts clean up; codec tests pass.

**M7: polish.** `Enforce/Reply` (with its control and preview line on the Settings tab), `UI/Wizard`, German locale completion, settings migration test. *Accept:* auto-reply obeys every rule in 6.4; first-run wizard appears once; the language switch works.

**M8: community, Friends and Guild.** `Hash`, `Report`, `Aggregate`, `Rules`, `Consent`, `Roster`, `Net`, the Community tab, tooltip and marker integration. Build in this order and stop for review after each step: (1) Aggregate and tiers with injected test data; (2) Resolver integration and rules; (3) Hash, Report and Net validation, tested with synthetic messages; (4) Consent UI and the rule editor; (5) Roster and transport (guild first, then friends); (6) display polish. *Accept:* nothing is sent or accepted while consent is missing; each toggle works independently; retract removes a report from a second client; hidden flags suppress enforcement; all validation tests pass.

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
