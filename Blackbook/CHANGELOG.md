# Changelog

All notable changes to Blackbook are listed here. The format follows Keep a Changelog and the project uses Semantic Versioning.

## [Unreleased]

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
