# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/agentjido/jido_browser/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/agentjido/jido_browser/releases/tag/v0.1.0
