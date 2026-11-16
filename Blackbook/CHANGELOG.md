# Changelog

All notable changes to Blackbook are listed here. The format follows Keep a Changelog and the project uses Semantic Versioning.

## [Unreleased]

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
