# Changelog

All notable changes to Nullgate's Blacklist (formerly Blackbook) are listed here. The format follows Keep a Changelog and the project uses Semantic Versioning.

## [Unreleased]
### Changed
- **Languages:** only the languages the game client runs in are offered now: English, German, Spanish, French, Italian, Portuguese, Russian, Korean, and Simplified and Traditional Chinese (new). Indonesian, Japanese, Turkish, Vietnamese, Polish and Ukrainian were removed. If you had picked one of them, the addon now follows your game's language.

## [1.0.0] - 2026-11-18
### Changed
- **Blackbook is now Nullgate's Blacklist - Forever**, part of the Nullgate addon suite.
- **This is a fresh start:** the addon folder is now `NullgatesBlacklist-Forever`, so your Blackbook list, imported lists and settings are not carried over. The setup wizard runs again on first login.
- The slash commands are now `/nbl` and `/blacklist`. `/blackbook` and `/bb` no longer work.
- Delete the old `Blackbook` folder from `Interface\AddOns`. If it is still installed, you are offered a button to disable it, because running both makes everything happen twice.
- List codes and friends and guild reports still work with older versions.
- **Global reports are kept apart from friends and guild.** They now use their own scrambling, so a report seen on the global channel can't be matched against friends and guild reports. Global reports from 1.0.0-alpha.2 and earlier no longer match, and fade out on their own.

### Added
- **Report card.** Right-click a player and choose **Report card** to see everything known about them in one window: your own entry, imported lists, and what friends, guild and the global channel report, with each reason and how many players reported it. Friends and guild reports show which character sent them; global reports only ever show a count.

## [1.0.0-alpha.2] - 2026-11-16
### Added
- **The global channel.** Besides friends and guild you can now share and receive reports on a global channel that every Blackbook user who switched it on joins. It is its own world: separate switches, separate data, higher thresholds (a flag needs many more reporters) and rules that only react from tier 3. It is public, so the first time you turn a global switch on you get a notice of its own that you must accept, and "Revoke and delete" withdraws it again.
- The channel is invisible in your chat: it is joined only while a global switch is on, left when both are off, taken out of every chat window, and its join messages are hidden. Messages on it are scrambled with a key that changes every hour. That is obfuscation, not secrecy, and the notice says so.
- Reports are passed on once, after a random 5 to 60 seconds, so they reach players who were not listening when they were first sent, and never loop. There are limits per sender and for all senders together against floods.
- **Test mode.** Turn on "Test mode" on the Settings tab (or type `/bb test mode`) and every other player's tooltip shows a sample of what Blackbook can say: your own ignore or warning, an imported list, a guild flag, friends and guild together, or a global flag. Different players show different examples, the last line says it is sample data, and your own character is left alone. It switches itself off when you log out.
- `/bb check` also reports whether the client has the channel functions global sharing needs.
- The Rules tab offers Global as a source and moves the tier to 3 when you choose it.

### Changed
- All fifteen languages cover the new texts (machine translated, apart from English and German).

## [1.0.0-alpha] - 2026-11-16
First alpha of Blackbook 1.0. It gathers everything built so far into one release for wider testing.

### What it does
- A personal list of players you ignore or warn about, each with reasons and a comment. Ignored players' chat is hidden and their invites, duels and trades are declined; warned players get an icon in chat, a mark on the target frame and a tooltip line.
- Share lists as codes and import other players' lists with your own rules for what each reason means.
- Optional, silent sharing of your Ignore entries with friends and guild as hashed reports, with a one-time consent, your own rules for acting on them, and a way to revoke everything. Friends and guild are kept apart from the global channel, which is not built yet.
- Optional automatic reply to whispers from players you ignore, a first-run setup wizard, and `/bb check` to test the client and the sharing connection on your own.
- Fifteen languages, switchable at once. Apart from English and German they are machine translated and unchecked.

### Known limits of this alpha
- It has been tested only with automated tests, not yet in the real game client. Expect rough edges in layout and in the parts that depend on game interface names.
- Friends sharing uses character friends only; Battle.net friends are not reached. Whispering a two-part name may not work on every client, which `/bb check` will show.
- The global channel is not part of this release.

## [0.10.1] - 2026-11-16
### Changed
- The windows are back in the game's own style, like its built-in dialogs: the framed dark panel with a gold title bar and close button, red panel buttons, standard tick boxes and text fields, and the game's fonts. The flat dark look from 0.9.0 is gone.
- The tab bar and the buttons are the game's standard buttons again; the active tab is the one that is greyed out.

## [0.10.0] - 2026-11-16
### Added
- Blackbook now speaks fifteen languages: English, Chinese (Simplified), Spanish, French, Portuguese, Russian, Indonesian, German, Japanese, Turkish, Vietnamese, Korean, Italian, Polish and Ukrainian. Pick one from the language list on the Settings tab or in the setup wizard, or with `/bb lang <code>`. "Automatic" follows your game's language where there is a matching translation.
- These are the most spoken languages that the game can display. Hindi, Arabic, Bengali and Urdu are left out because the game has no font for those scripts.

### Note
- Apart from English and German, the translations were produced by machine and have not been checked by native speakers, so some wording may be stiff or wrong. Corrections are welcome.

## [0.9.0] - 2026-11-16
### Changed
- A new modern look for every window: a flat dark panel with a thin border, a title bar with a gold line, and calm grey text. The list window, the editor, the setup wizard and all their tabs use it.
- Buttons are flat and react to the mouse. The main action of each window is gold (Save, Next, Confirm, Add rule, Create code, Import), destructive ones have red text (Revoke and delete, Remove list), and a disabled button looks switched off.
- Tick boxes, text fields and tabs are redrawn to match: ticked boxes fill with gold, a text field's border turns gold while you type in it, and the active tab has a gold line under it.
- The addon uses its own sans-serif font, so none of the game's other text is affected. Chinese, Japanese and Korean will keep the game's standard font when those languages are added.

## [0.8.1] - 2026-11-16
### Fixed
- On the last page of the setup wizard the Finish button showed the whole page text, which ran across the screen and over the other buttons. It now says "Finish".
- The setup wizard has less empty space between its text and its controls.

### Changed
- The language changes at once. There is no `/reload` any more: the window, the editor and the wizard are rebuilt in the new language the moment you pick it.
- The language choice is a dropdown instead of a row of tick boxes, so it has room for many languages. Each language is listed under its own name. `/bb lang` lists the codes it accepts.

## [0.8.0] - 2026-11-16
### Added
- `/bb check` tests this client without needing anyone else. It lists which features Blackbook relies on (chat filter, right-click menu, tooltips, lists, dropdowns, popups, addon messages, friend list and more) and marks any that are missing. It then whispers a short message to your own character and waits for it to come back, which shows whether sharing with friends and guild can work on your client.
- Automatic reply to whispers from players you ignore, off by default. Choose off, a short sentence, or one that names your reasons. It is sent once per player and session after a moment, in your language, never contains your comment, and the copy of it in your own chat is hidden. Only players you ignored yourself get a reply, not players flagged by an imported list or by the community. The Settings tab shows a preview of the sentence.
- A first-run setup wizard in four short steps: language, what Ignore does, the automatic reply, and the minimap button. It opens once after login. `/bb setup` or the new button on the Settings tab opens it again. It never switches sharing on.

### Changed
- `/bb setup` now opens the wizard instead of saying it is not available.
- Saved data is checked and repaired more thoroughly when it loads, so a damaged or very old save no longer causes errors.
- The English and German texts are checked against each other automatically.

## [0.7.0] - 2026-11-16
### Added
- Automatic, silent sharing with friends and guild. After you confirm the notice once on the new **Community** tab and switch a source on, Blackbook reports your Ignore entries in the background and receives reports from others. No popups, no prompts and no chat output. What is sent is a hash of the player's name, the reason labels, a day number and an anonymous token, never names, comments or your own name. You see exactly what would be sent with the preview button.
- Friends and guild each have their own send and receive switch. They are kept apart from each other's data and from the global channel (not built yet), which will never be mixed in.
- Reports only ever add a notice. The new **Rules** tab lets you decide per source, reason and tier whether they mean warn or ignore. A rule that ignores asks for confirmation first.
- Tooltips show one line per source, for example "Guild: 7 players reported this player (Elevated)". The chat icon, target mark and tooltip use the notice look.
- "This flag is wrong" in the right-click menu hides a community flag on this install. The Rules tab lists hidden flags and brings them back with a click.
- "Revoke and delete" stops all sharing, withdraws your reports where possible and deletes everything received.

### Changed
- The tab bar fits seven tabs. The German name of the Settings tab is now "Optionen".

### Removed
- The "Send my list" menu entry and the in-game list offers with their popup. Automatic sharing replaces them. List codes (export and import on the Share tab) stay.

## [0.6.0] - 2026-11-16
### Added
- Share your list as a code. The new **Share** tab turns your records into a list code (`BK1...`) that you can copy, paste anywhere and import on another account. You choose the list name, which reasons are included and whether your comments go with it.
- Import a code from the Share tab. Blackbook checks it fully (checksum, sizes, every record) and tells you what is wrong if it is damaged, then asks for confirmation showing the list name, author, size and date.
- Imported lists get their own tabs. **Imported** shows every entry of every list with the verdict that applies; click one to add that player to your own list. **Lists** lets you decide for each list and each reason whether it means notice, warn or ignore, and remove a list with Shift-click.
- Send your list to another player in game, from the Share tab or the right-click menu ("Send my list"). The other player gets a popup and can accept or decline. Offers from players you ignore are dropped without a reply.
- Your own entries still win over any imported list.

### Safety
- A list can never contain your own character, so it cannot hide your own chat. Names with control characters or colour codes are refused, codes and transfers are size-limited, and at most 50 lists are kept.

## [0.5.2] - 2026-11-16
### Fixed
- The list window and the editor are drawn above other addons' frames (unit frames, buff bars, progress bars) instead of behind them, and come to the front when clicked.

## [0.5.1] - 2026-11-16
### Added
- `/bb test <ignore|warn|notice>` shows a sample chat line with that verdict's icon, so the markers can be checked without a flagged player speaking.

## [0.5.0] - 2026-11-16
### Added
- Chat from players you warned about, or that only an imported list flags, now shows an icon in front of each line. If you turn chat hiding off, ignored players' lines carry a red cross.
- The target frame shows a mark for flagged players: a diagonal strike for Ignore and a corner icon for Warn and Notice.
- Player tooltips list the verdict, the reasons, your comment and up to three imported lists that flag the player.
- Blackbook has its own icon in the add-on list and on the minimap button.

## [0.4.0] - 2026-11-16
### Added
- The list window (`/bb`, or click the minimap button) with a "My list" tab: search, verdict and label filters, sortable columns, a scrolling list with tooltips, an add-player box, click to edit and Shift-click to delete. The scroll position stays put when the list changes.
- A "Settings" tab with the language and the hide-chat, auto-decline, notice and minimap options. Changes apply immediately.
- A minimap button that you can drag around the edge. Its position is remembered. `/bb minimap` shows or hides it.

### Changed
- `/bb` with no arguments now opens the window instead of saying it is not available.

## [0.3.1] - 2026-11-16
### Fixed
- The Save and Cancel buttons in the editor could not be clicked because the comment box covered them. The window is now tall enough and its layout can no longer overlap.

## [0.3.0] - 2026-11-16
### Added
- A proper editor window for records: choose Ignore or Warn, pick reasons from a dropdown (a checkbox list is used if the client has no dropdown), write a comment with a live character counter. Save stays disabled until the entry is valid.
- Right-click menus on players (unit frames, party and raid, friends, chat names, guild and community lists) offer Ignore, Warn, Edit, Remove and, for players only an imported list knows, Adopt.
- The editor can be dragged and closes with Escape.

### Changed
- Renaming a record in the editor moves it, and a name that already has a record is refused instead of being overwritten.
- The comment limit of 255 now counts characters, so umlauts count once.

## [0.2.1] - 2026-11-16
### Fixed
- Blackbook failed to load its saved data on the game client because of a missing random-number function. It now starts normally.

## [0.2.0] - 2026-11-16
### Added
- Chat from ignored players is hidden in every channel. A hidden whisper is announced at most once a minute per person.
- Party invites, guild invites, duels and trades from ignored players are declined automatically, with a notice.
- Players on imported lists get a verdict from your per-label rules, and your own entries always win.

### Fixed
- Saved data written by a newer version of Blackbook is no longer modified.
- One failing internal handler can no longer stop the others.

## [0.1.0] - 2026-11-16
### Added
- Personal blocklist with `/bb ignore`, `/bb warn`, `/bb remove` and `/bb list`. Each entry needs at least one reason and a comment.
- `/bb version` shows the installed version.
- English and German texts.
