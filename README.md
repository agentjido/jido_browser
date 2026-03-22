# Jido Browser

[![Hex.pm](https://img.shields.io/hexpm/v/jido_browser.svg)](https://hex.pm/packages/jido_browser)
[![Docs](https://img.shields.io/badge/docs-hexdocs-blue.svg)](https://hexdocs.pm/jido_browser)
[![CI](https://github.com/agentjido/jido_browser/actions/workflows/ci.yml/badge.svg)](https://github.com/agentjido/jido_browser/actions/workflows/ci.yml)

Browser automation for Jido AI agents.

## Overview

`Jido.Browser` is an agent-browser-first browser automation library for Jido.

- `agent-browser` is the default and only first-class backend in 2.0
- each browser session is backed by a supervised external daemon
- Elixir talks to the daemon over the upstream local JSON socket/TCP protocol
- `Vibium` and `Web` remain available as legacy, feature-frozen adapters for transitional use

The Hex package and OTP app remain `jido_browser`, while the public Elixir namespace is `Jido.Browser.*`.

## Installation

Add the dependency:

```elixir
def deps do
  [
    {:jido_browser, "~> 2.0"}
  ]
end
```

Install the default browser backend:

```bash
mix jido_browser.install
```

That installs the pinned `agent-browser` binary for the current platform and runs `agent-browser install` to provision the browser runtime.

### Recommended Alias Setup

```elixir
defp aliases do
  [
    setup: ["deps.get", "jido_browser.install --if-missing"],
    test: ["jido_browser.install --if-missing", "test"]
  ]
end
```

### Installing Specific Backends

```bash
mix jido_browser.install agent_browser
mix jido_browser.install vibium
mix jido_browser.install web
```

## Quick Start

```elixir
{:ok, session} = Jido.Browser.start_session()

{:ok, session, _} = Jido.Browser.navigate(session, "https://example.com")
{:ok, session, snapshot} = Jido.Browser.snapshot(session)

snapshot["snapshot"] || snapshot[:snapshot]

{:ok, session, _} = Jido.Browser.click(session, "@e1")
{:ok, _session, %{content: markdown}} = Jido.Browser.extract_content(session, format: :markdown)

:ok = Jido.Browser.end_session(session)
```

Selectors remain supported, but ref-based interaction is the preferred 2.0 flow:

1. `snapshot`
2. act on `@eN` refs
3. re-snapshot

### Stateless Web Fetch

```elixir
{:ok, result} =
  Jido.Browser.web_fetch(
    "https://example.com/docs",
    format: :markdown,
    allowed_domains: ["example.com"],
    focus_terms: ["API", "authentication"],
    citations: true
  )

result.content
result.passages
```

### State Persistence

```elixir
state_path = Path.expand("tmp/browser-state.json")
File.mkdir_p!(Path.dirname(state_path))

{:ok, session} = Jido.Browser.start_session()
{:ok, session, _} = Jido.Browser.navigate(session, "https://example.com")
{:ok, session, _} = Jido.Browser.save_state(session, state_path)
:ok = Jido.Browser.end_session(session)

{:ok, restored} = Jido.Browser.start_session()
{:ok, restored, _} = Jido.Browser.load_state(restored, state_path)
```

### Tab Workflow

```elixir
{:ok, session} = Jido.Browser.start_session()
{:ok, session, _} = Jido.Browser.navigate(session, "https://example.com")
{:ok, session, _} = Jido.Browser.new_tab(session, "https://example.org")
{:ok, session, tabs} = Jido.Browser.list_tabs(session)
{:ok, session, _} = Jido.Browser.switch_tab(session, 1)
{:ok, session, _} = Jido.Browser.close_tab(session, 1)
```

### Plugin Setup

```elixir
defmodule MyBrowsingAgent do
  use Jido.Agent,
    name: "browser_agent",
    plugins: [
      {Jido.Browser.Plugin,
       [
         adapter: Jido.Browser.Adapters.AgentBrowser,
         headless: true,
         timeout: 30_000
       ]}
    ]
end
```

## Configuration

```elixir
config :jido_browser,
  adapter: Jido.Browser.Adapters.AgentBrowser

config :jido_browser, :agent_browser,
  binary_path: "/usr/local/bin/agent-browser",
  headed: false
```

Legacy adapters can still be configured explicitly:

```elixir
config :jido_browser, :vibium,
  binary_path: "/path/to/vibium"

config :jido_browser, :web,
  binary_path: "/usr/local/bin/web",
  profile: "default"
```

Optional web fetch settings:

```elixir
config :jido_browser, :web_fetch,
  cache_ttl_ms: 300_000,
  pdftotext_path: "/usr/local/bin/pdftotext"
```

## Backends

### AgentBrowser (Default)

- native snapshot support with refs
- supervised daemon per session
- direct JSON IPC from Elixir
- built-in state save/load and tab management support

### Vibium (Legacy)

- retained for transitional compatibility
- feature-frozen in 2.0

### Web (Legacy)

- retained for transitional compatibility
- feature-frozen in 2.0

## Public API

Core operations:

- `start_session/1`
- `end_session/1`
- `navigate/3`
- `click/3`
- `type/4`
- `screenshot/2`
- `extract_content/2`
- `web_fetch/2`
- `evaluate/3`

Agent-browser-native operations:

- `snapshot/2`
- `wait_for_selector/3`
- `wait_for_navigation/2`
- `query/3`
- `get_text/3`
- `get_attribute/4`
- `is_visible/3`
- `save_state/3`
- `load_state/3`
- `list_tabs/2`
- `new_tab/3`
- `switch_tab/3`
- `close_tab/3`
- `console/2`
- `errors/2`

## Available Actions

### Session

- `StartSession`
- `EndSession`
- `GetStatus`
- `SaveState`
- `LoadState`

### Navigation

- `Navigate`
- `Back`
- `Forward`
- `Reload`
- `GetUrl`
- `GetTitle`

### Interaction

- `Click`
- `Type`
- `Hover`
- `Focus`
- `Scroll`
- `SelectOption`

### Waiting and Queries

- `Wait`
- `WaitForSelector`
- `WaitForNavigation`
- `Query`
- `GetText`
- `GetAttribute`
- `IsVisible`

### Content and Diagnostics

- `Snapshot`
- `Screenshot`
- `ExtractContent`
- `Console`
- `Errors`

### Tabs

- `ListTabs`
- `NewTab`
- `SwitchTab`
- `CloseTab`

### Advanced and Composite

- `Evaluate`
- `ReadPage`
- `SnapshotUrl`
- `SearchWeb`
- `WebFetch`

## Using With Jido Agents

```elixir
defmodule MyBrowsingAgent do
  use Jido.Agent,
    name: "web_browser",
    description: "An agent that can browse the web",
    plugins: [{Jido.Browser.Plugin, [headless: true]}]
end
```

`Jido.Browser.Plugin` now exposes 37 browser actions, including snapshot/refs workflows, browser state actions, diagnostics, and tab management.

## License

Apache-2.0 - See [LICENSE](LICENSE) for details.
