# Nullgate's Blacklist - Forever

[![Interface](https://img.shields.io/badge/Interface-16001%20(WoW%20Forever)-0078D7.svg?style=flat-square)](https://github.com/nullgatestudios/NullgatesBlacklist-Forever)
[![Release](https://img.shields.io/badge/Release-v1.0.0-ffd100.svg?style=flat-square)](https://github.com/nullgatestudios/NullgatesBlacklist-Forever/releases)
[![License](https://img.shields.io/badge/License-Source--Available-crimson.svg?style=flat-square)](LICENSE.md)
[![Dependencies](https://img.shields.io/badge/Dependencies-None-2ea44f.svg?style=flat-square)](https://github.com/nullgatestudios/NullgatesBlacklist-Forever)

**Nullgate's Blacklist** keeps a personal list of the players you never want to deal with again in **World of Warcraft: Forever**, and quietly keeps them out of your way.

Ignore someone and their chat disappears, and their party invites, guild invites, duels and trades are declined for you. Warn about someone and you get a clear marker wherever they show up: in chat, on your target frame and in their tooltip. You can also share what you know with friends and your guild, and see at a glance what they've reported.

*Formerly **Blackbook**. Part of the Nullgate addon suite.*

---

## Key Highlights

- **Ignore or Warn**: Two levels for every player. Ignore hides their chat and declines their invites, duels and trades. Warn only marks them, so you can decide for yourself.
- **Reasons and Comments**: Tag each entry with reasons (scam, spam, loot stealing, griefing, harassment and more) and add a private comment only you can see.
- **Markers Everywhere**: Warned and ignored players get an icon in chat, a mark on your target frame and a line in their tooltip.
- **Report Card**: Right-click any player and choose **Report card** to see everything known about them in one window: your own entry, imported lists, and what friends, guild and the global channel have reported.
- **Share Lists**: Turn your list into a code to share, and import other players' lists. You decide what each reason means for you.
- **Community Reports (optional)**: Share your Ignore entries with friends and your guild, and receive theirs. Nothing is shared until you read a short notice and switch it on.
- **Global Channel (optional)**: Pool reports with every Nullgate's Blacklist player who joins. Global reports are anonymous and need many reporters before they count.
- **10 Languages**: every language the game client runs in. Switch at any time; it changes at once.

---

## The Report Card

Right-click a player (in chat, on their portrait, in your friends or guild list) and choose **Report card**. It shows:

- **Your list**: your verdict, reasons and comment, if you have an entry for them.
- **Imported lists**: which lists you've imported include them.
- **Friends and guild**: how many players reported them, for which reasons, and **which character sent each report**, with how long ago.
- **Global**: how many players reported them and for which reasons. **Global reports are anonymous**, so no names are ever shown.

Reports that haven't reached the first tier yet still appear, marked as such, so you can see when something is building up.

---

## Community Reports: How They Work

- **Only what you choose is shared**: only players you **Ignore**, only the reasons you pick, and **never your comments**.
- **Names are hashed, not sent**: reports carry a scrambled version of the player's name, the reasons, a day and an anonymous token. This stops casual browsing, but it isn't encryption: anyone can hash a list of names they already know.
- **Friends and guild see who reported**: friends and guild members who receive your report can see which of your characters sent it.
- **Global is anonymous and kept apart**: global reports use their own scrambling, so they can't be matched against friends and guild reports, and the report card never shows who sent them.
- **Reports alone never block anyone**: received reports only add a notice. They affect chat or invites only through **rules you create** on the Rules tab, such as "warn me when two guild members report Scam".
- **Tiers**: Flag, Elevated, Urgent and Critical, depending on how many players reported recently. Global reports need far more reporters, and global rules only react from Urgent.
- **"This flag is wrong"**: hide a community flag about a player on your own install. Nothing is shared.
- **Revoke and delete**: stop sharing at any time. Your reports are withdrawn where possible and everything you received is deleted.

---

## Slash Commands

| Command | Action |
| :--- | :--- |
| `/nbl` or `/blacklist` | Open or close the list window. |
| `/nbl ignore <name>` | Ignore a player. |
| `/nbl warn <name>` | Warn about a player. |
| `/nbl remove <name>` | Delete an entry. |
| `/nbl list` | Show your list in chat. |
| `/nbl setup` | Show the setup wizard again. |
| `/nbl minimap` | Show or hide the minimap button. |
| `/nbl lang <code\|auto>` | Change the language at once. |
| `/nbl test mode` | Show sample lines on tooltips, to see what the addon looks like. |
| `/nbl check` | Test your client and the sharing connection. |
| `/nbl help` | List every command. |

---

## Settings

- **Hide chat** from ignored players.
- **Decline invites, duels and trades** from ignored players.
- **Show a notice** when something is blocked.
- **Automatic reply** to whispers from ignored players: off, short, or with reasons. Each player gets one reply per session, never your comment.
- **Minimap button** on or off.
- **Language**: automatic or any of the 10 available.

---

---

## Installation

1. Download the latest release from CurseForge or the [GitHub releases](https://github.com/nullgatestudios/NullgatesBlacklist-Forever/releases) page.
2. Extract the `NullgatesBlacklist-Forever` folder into the `Interface\AddOns` folder of your World of Warcraft: Forever installation.
3. **Coming from Blackbook?** Delete the old `Blackbook` folder. Nullgate's Blacklist is a fresh start: your Blackbook list and settings are not carried over.
4. Log in. A short setup wizard walks you through the basics.

---

## Development

| Task | Command |
| :--- | :--- |
| Run the tests | `lua tests/run.lua` and `lua tests/smoke.lua` |
| Build `zips/NullgatesBlacklist-Forever-<version>.zip` | `powershell -ExecutionPolicy Bypass -File tools/package.ps1` |

The design, data formats and wire protocol are described in [DESIGN.md](DESIGN.md). Publishing a GitHub release uploads that version to CurseForge. No third-party libraries are bundled.

---

## License & Support

- **License**: Restricted - Source-Available (All Rights Reserved, No Derivatives). See [LICENSE.md](LICENSE.md) for the full terms.
- **Issues & feedback**: open an issue on the [GitHub issue tracker](https://github.com/nullgatestudios/NullgatesBlacklist-Forever/issues).
- **Author**: Nullgate Studios
