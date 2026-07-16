# Changelog

All notable changes to AriaFlow are documented in this file.

## Unreleased

### Added

- Added direct Telegram video and media downloads from message links through a locally installed `tdl`.
- Added Telegram task validation, sequential process orchestration, pause/resume, grouped-message handling, task history, and tdl status guidance.
- Added live Telegram progress, downloaded size, percentage, transfer speed, and ETA from `tdl` output.

### Changed

- Kept task and history views usable when the aria2 engine is unavailable but Telegram downloads are available.
- Included active Telegram transfers in the app-wide download speed and Dock progress.

### Fixed

- Preserved the exact directory selected in the new-task sheet and showed the resolved save path on Telegram task rows.

## 0.2.0 - 2026-07-15

### Added

- Added local BitTorrent peer blocklist selection, validation, runtime reload, and clearing.

### Changed

- Updated bundled `aria2-next` sidecars from 2.4.9 to 2.5.1.
- Updated the engine log level to the 2.5.x-compatible `info` value.
- Consolidated developer documentation around architecture, sidecar, release, and agent recovery context.

### Fixed

- Activated the Settings window correctly on macOS 15.
- Prevented the main window from flashing when launching in menu-bar mode.
- Restored native Command-drag repositioning for the menu-bar item.

## 0.1.1 - 2026-07-11

### Changed

- Lowered the deployment target to macOS 14.
- Kept Liquid Glass controls on macOS 26 and added standard material/button fallbacks for macOS 14 and 15.

### Fixed

- Preserved menu-bar launch behavior without relying on macOS 15-only scene APIs.
- Disabled main-window state restoration through the cross-version AppKit window path.

### Known Limitations

- Archives use ad-hoc signing and are not notarized; Gatekeeper may require explicit user confirmation.

## 0.1.0 - 2026-07-11

### Added

- Native SwiftUI macOS download manager with URL, magnet, ED2K, and torrent tasks.
- Bundled universal `aria2-next 2.4.9` engine sidecars for Apple Silicon and Intel Macs.
- Queue controls, task actions, history, menu bar status, Dock progress, and configurable download settings.
- Release packaging, checksum generation, local smoke tests, and GitHub release automation.

### Known Limitations

- Requires macOS 26 or later.
- `v0.1.0` archives use ad-hoc signing and are not notarized; Gatekeeper may require an explicit user confirmation.
- AriaFlow is local-only and does not manage remote aria2 instances, accounts, cloud sync, or browser extensions.
