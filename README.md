# Jido Browser

[![Hex.pm](https://img.shields.io/hexpm/v/jido_browser.svg)](https://hex.pm/packages/jido_browser)
[![Docs](https://img.shields.io/badge/docs-hexdocs-blue.svg)](https://hexdocs.pm/jido_browser)
[![CI](https://github.com/agentjido/jido_browser/actions/workflows/ci.yml/badge.svg)](https://github.com/agentjido/jido_browser/actions/workflows/ci.yml)

Browser automation for Jido AI agents.

## Overview

`Jido.Browser` is organized around three simple lanes:

- `web_fetch/2` for stateless HTTP-first retrieval
- `start_session/1` and `end_session/1` for browser-backed workflows
- `Jido.Browser.Pool` plus `start_session(pool: ...)` as an optional acceleration layer

`agent-browser` remains the default adapter. `Web` also supports warm pools when
you want browser-backed sessions with lower cold-start overhead. `Vibium`
remains available without warm-pool support.

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
result.metadata # present when extraction returns document metadata
```

`web_fetch/2` keeps HTML handling native for selector extraction and markdown conversion, and uses `extractous_ex` for fetched binary documents such as PDFs, Word, Excel, PowerPoint, OpenDocument, EPUB, and common email formats. Binary document responses may also include `result.metadata` when extraction returns document metadata.

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

### Warm Session Pools

Warm pools are explicit and optional. They speed up browser-backed workflows,
while `web_fetch/2` stays stateless and never uses pools.

For OTP applications, prefer adding a named pool to your supervision tree:

```elixir
defmodule MyApp.Application do
  use Application

  def start(_type, _args) do
    children = [
      {Jido.Browser.Pool,
       name: :default,
       size: 2,
       headless: true,
       startup_timeout: 60_000}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: MyApp.Supervisor)
  end
end
```

Then check out pooled sessions by name:

```elixir
{:ok, session} =
  Jido.Browser.start_session(
    pool: :default,
    checkout_timeout: 5_000
  )

{:ok, session, _} = Jido.Browser.navigate(session, "https://example.com")
:ok = Jido.Browser.end_session(session)
```

Use `start_pool/1` for scripts, tests, or ad hoc startup:

```elixir
{:ok, _pool} =
  Jido.Browser.start_pool(
    name: :default,
    size: 2,
    headless: true
  )

{:ok, session} =
  Jido.Browser.start_session(
    pool: :default,
    checkout_timeout: 5_000
  )

{:ok, session, _} = Jido.Browser.navigate(session, "https://example.com")
:ok = Jido.Browser.end_session(session)
```

Warm pools are currently supported by `Jido.Browser.Adapters.AgentBrowser` and
`Jido.Browser.Adapters.Web`.

- AgentBrowser pools keep full warm daemon-backed sessions ready for checkout.
- Web pools keep reserved warmed profiles ready for checkout.
- `end_session/1` always recycles the checked-out worker and warms a replacement
  in the background.

For the `Web` adapter, pooled sessions are still browser sessions, not HTTP
fetches. Use `web_fetch/2` when you want the simplest request/response API
without browser state.

### Plugin Setup

```elixir
defmodule MyBrowsingAgent do
  use Jido.Agent,
    name: "browser_agent",
    plugins: [
      {Jido.Browser.Plugin,
       [
         adapter: Jido.Browser.Adapters.AgentBrowser,
         pool: :default,
         checkout_timeout: 5_000,
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

Other adapters can still be configured explicitly:

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
  extractous: [
    pdf: [extract_annotation_text: true],
    office: [include_headers_and_footers: true]
  ]
```

Configured `extractous` options are merged with any per-call `extractous:` keyword options passed to `Jido.Browser.web_fetch/2`.

## Backends

### AgentBrowser (Default)

- native snapshot support with refs
- supervised daemon per session
- optional warm session pools with explicit checkout
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

- `start_pool/1`
- `stop_pool/1`
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
