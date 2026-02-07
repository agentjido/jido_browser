# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.8.1] - 2026-02-06

### Changed

- Renamed `Plugin.router/1` to `Plugin.signal_routes/1` to align with Jido 2.0.0-rc.4 Plugin API

### Fixed

- Removed invalid `@impl` from `Plugin.router/1` callback

### Chore

- Upgraded `jido` to ~> 2.0.0-rc.4
- Upgraded `jido_action` to ~> 2.0.0-rc.4

## [0.8.0] - 2025-02-04

### Added

- `JidoBrowser.Plugin` - Jido.Plugin bundling all browser actions with lifecycle management
- `JidoBrowser.Installer` - Automatic binary installation with platform detection
- `mix jido_browser.install` - Mix task for installing browser backends (Vibium, Web)
- 20 new browser actions: Back, Forward, Reload, GetUrl, GetTitle, Hover, Focus, Scroll, SelectOption, Wait, WaitForSelector, WaitForNavigation, Query, GetText, GetAttribute, IsVisible, Snapshot, StartSession, EndSession, GetStatus

### Changed

- Renamed `Jido.Skill` to `Jido.Plugin` following Jido 2.0 conventions
- Installer now uses `_build/jido_browser` directory instead of `~/.jido_browser`
- Updated dependencies: jido ~> 2.0.0-rc, jido_action ~> 2.0.0-rc

### Fixed

- Removed unreachable pattern matches flagged by Dialyzer

## [0.1.0] - 2025-01-29

### Added

- Initial release
- Core `JidoBrowser` module with session management
- `JidoBrowser.Session` struct with Zoi schema
- `JidoBrowser.Adapter` behaviour for pluggable backends
- `JidoBrowser.Adapters.Vibium` - Vibium/WebDriver BiDi adapter
- `JidoBrowser.Adapters.Web` - chrismccord/web CLI adapter
- `JidoBrowser.Error` module with Splode error types
- Jido Actions:
  - `JidoBrowser.Actions.Navigate`
  - `JidoBrowser.Actions.Click`
  - `JidoBrowser.Actions.Type`
  - `JidoBrowser.Actions.Screenshot`
  - `JidoBrowser.Actions.ExtractContent`
  - `JidoBrowser.Actions.Evaluate`

[Unreleased]: https://github.com/agentjido/jido_browser/compare/v0.8.0...HEAD
[0.8.0]: https://github.com/agentjido/jido_browser/compare/v0.1.0...v0.8.0
[0.1.0]: https://github.com/agentjido/jido_browser/releases/tag/v0.1.0
