# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

[Unreleased]: https://github.com/agentjido/jido_browser/compare/v2.3.0...HEAD

<!-- changelog -->

## [v2.3.0](https://github.com/agentjido/jido_browser/compare/v2.2.0...v2.3.0) (2026-08-27)




### Bug Fixes:

* browsey: handle fast process exits without a PID race (#113) by mikehostetler

* installer: stop on all browser installation failures (#106) by mikehostetler

* agent_browser: make binary selection deterministic (#104) by mikehostetler

* agent_browser: support AgentBrowser 0.35.1 daemon payloads (#100) by mikehostetler

### Refactoring:

* session: derive the struct contract from Zoi (#101) by mikehostetler

* plugin: define actions and routes once (#99) by mikehostetler

### Deprecated:

* adapters: publish support tiers and warnings (#108) by mikehostetler

### Security:

* web_fetch: cap response bytes during transport (#109) by mikehostetler

* web_fetch: enforce destination and redirect policy (#105) by mikehostetler

## [v2.2.0](https://github.com/agentjido/jido_browser/compare/v2.1.0...v2.2.0) (2026-08-10)




### Features:

* harden agent browser retrieval by mikehostetler

* add vendored Browsey web fetch backend by Matthew Neel

* add Lightpanda browser adapter by Matthew Neel

### Bug Fixes:

* deps: update Mint for CVE-2026-59249 by mikehostetler

* support Elixir 1.20 strict compile by mikehostetler

* honor adapter session defaults by mikehostetler

* harden vendored browsey backend by mikehostetler

## [v2.1.0](https://github.com/agentjido/jido_browser/compare/v2.0.0...v2.1.0) (2026-05-23)




### Features:

* add warm agent-browser session pools (#26) by mikehostetler

## [v2.0.0](https://github.com/agentjido/jido_browser/compare/v1.0.0...v2.0.0) (2026-03-14)
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

[1.0.0]: https://github.com/agentjido/jido_browser/compare/v0.8.1...v1.0.0
[0.8.1]: https://github.com/agentjido/jido_browser/compare/v0.8.0...v0.8.1
[0.8.0]: https://github.com/agentjido/jido_browser/compare/v0.1.0...v0.8.0
[0.1.0]: https://github.com/agentjido/jido_browser/releases/tag/v0.1.0
