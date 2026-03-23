# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- Rename the public Elixir namespace from `JidoBrowser.*` to `Jido.Browser.*`
- Keep source and test files in `lib/jido_browser/**` and `test/jido_browser/**` while exposing the `Jido.Browser.*` namespace

### Fixed

- Sync `mix.lock` with the stable `jido ~> 2.0` / `jido_action ~> 2.0` dependency declarations in `mix.exs`

## [1.0.0] - 2026-02-22

### Changed

- Promote package line from `0.8.x` to stable `1.0.0` for the Jido 2.0 ecosystem
- Upgrade ecosystem deps to stable ranges: `jido ~> 2.0`, `jido_action ~> 2.0`
- Update installation docs/examples to use `{:jido_browser, "~> 1.0"}`

### Fixed

- Harden integration fixture server to handle closed sockets without crashing task processes

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

- `Jido.Browser.Plugin` - Jido.Plugin bundling all browser actions with lifecycle management
- `Jido.Browser.Installer` - Automatic binary installation with platform detection
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
- Core `Jido.Browser` module with session management
- `Jido.Browser.Session` struct with Zoi schema
- `Jido.Browser.Adapter` behaviour for pluggable backends
- `Jido.Browser.Adapters.Vibium` - Vibium/WebDriver BiDi adapter
- `Jido.Browser.Adapters.Web` - chrismccord/web CLI adapter
- `Jido.Browser.Error` module with Splode error types
- Jido Actions:
  - `Jido.Browser.Actions.Navigate`
  - `Jido.Browser.Actions.Click`
  - `Jido.Browser.Actions.Type`
  - `Jido.Browser.Actions.Screenshot`
  - `Jido.Browser.Actions.ExtractContent`
  - `Jido.Browser.Actions.Evaluate`

[Unreleased]: https://github.com/agentjido/jido_browser/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/agentjido/jido_browser/compare/v0.8.1...v1.0.0
[0.8.1]: https://github.com/agentjido/jido_browser/compare/v0.8.0...v0.8.1
[0.8.0]: https://github.com/agentjido/jido_browser/compare/v0.1.0...v0.8.0
[0.1.0]: https://github.com/agentjido/jido_browser/releases/tag/v0.1.0

<!-- changelog -->

## [2.0.0](https://github.com/agentjido/jido_browser/compare/v2.0.0...2.0.0) (2026-03-14)
### Breaking Changes:

* rename browser API to Jido.Browser by mikehostetler



### Features:

* redesign jido browser around agent-browser (#21) by mikehostetler

* redesign jido browser around agent-browser by mikehostetler

### Bug Fixes:

* harden agent-browser integration paths by mikehostetler

* restore vibium compatibility and stabilize ci by mikehostetler

### Refactoring:

* streamline agent-browser runtime defaults by mikehostetler