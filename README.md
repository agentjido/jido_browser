# Jido Browser

[![Hex.pm](https://img.shields.io/hexpm/v/jido_browser.svg)](https://hex.pm/packages/jido_browser)
[![Hex Docs](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://hexdocs.pm/jido_browser/)
[![CI](https://github.com/agentjido/jido_browser/actions/workflows/ci.yml/badge.svg)](https://github.com/agentjido/jido_browser/actions/workflows/ci.yml)
[![License](https://img.shields.io/hexpm/l/jido_browser.svg)](https://github.com/agentjido/jido_browser/blob/main/LICENSE)
[![Website](https://img.shields.io/badge/website-jido.run-0f172a.svg)](https://jido.run)
[![Ecosystem](https://img.shields.io/badge/ecosystem-jido.run-0ea5e9.svg)](https://jido.run/ecosystem)
[![Discord](https://img.shields.io/badge/discord-join-5865F2.svg?logo=discord&logoColor=white)](https://jido.run/discord)

Browser automation for Jido AI agents.

## Overview

`Jido.Browser` is organized around three simple lanes:

- `web_fetch/2` for stateless HTTP-first retrieval
- `fetch_rich/2` for agent-friendly retrieval with optional browser fallback
- `start_session/1` and `end_session/1` for browser-backed workflows
- `Jido.Browser.Pool` plus `start_session(pool: ...)` as an optional acceleration layer

`agent-browser` is the default adapter and supports warm pools. `Vibium` remains
available without warm-pool support. `Lightpanda` is available as an optional
limited adapter for lightweight DOM and JavaScript automation, with warm-pool
support for prestarted CDP sessions.

The [browser adapter support policy](guides/browser_adapter_support.md) is the
canonical source for support levels, tested versions, CI coverage, and 3.0
removal notices.

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
mix jido_browser.install lightpanda
```

Lightpanda support uses optional dependencies. Add them to applications that
select `Jido.Browser.Adapters.Lightpanda`:

```elixir
def deps do
  [
    {:jido_browser, "~> 2.0"},
    {:light_cdp, "~> 0.2.1"},
    {:lightpanda_ex, "~> 0.1.0"}
  ]
end
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

`web_fetch/2` keeps HTML handling native for selector extraction and markdown
conversion. Document extraction is optional. Add `extractous_ex` to your
application when you need to fetch PDFs, Word, Excel, PowerPoint, OpenDocument,
EPUB, or common email formats:

```elixir
defp deps do
  [
    {:jido_browser, "~> 3.0"},
    {:extractous_ex, "~> 0.2"}
  ]
end
```

Binary document responses can include `result.metadata` when extraction returns
document metadata. Without `extractous_ex`, PDF and office document requests
return an adapter error with `error_code: :unsupported_feature` and
`feature: :document_extraction`. HTML and text retrieval and browser automation
do not load ExtractousEx or Rustler.

Web fetches reject loopback, private, link-local, and cloud metadata addresses by default. Set `allow_private_network: true` only when a fetch must reach a trusted private service. Domain allow and block rules still apply when this option is enabled.

Each HTTP response has a `max_response_bytes` limit. The default is 5 MiB. Set a
positive byte count to change it, or set `:infinity` only when compatibility
requires no Jido response limit. This limit is separate from
`max_content_tokens`, which truncates normalized content after retrieval and
extraction.

The Req backend counts the authoritative Finch body events after HTTP transfer
framing and before `Content-Encoding` decoding. It also counts each supported
decoded content layer while it streams. Both counts use the same public limit,
so a small gzip response cannot expand without a bound. Successful compressed
responses stay decoded. Error metadata reports `:transfer_body` or
`:content_decoded` in `response_byte_semantics`.

`Req` is the HTTP backend. Jido Browser 3.0 removes the `:browsey` backend,
`Jido.Browser.WebFetch.Backends.Browsey`, and the `browsey:` configuration key.
Use Req for stateless HTTP retrieval. Use AgentBrowser or enable
`browser_fallback` in `fetch_rich/2` when a page needs JavaScript or browser
rendering.

### Agent-Friendly Rich Fetch

Use `fetch_rich/2` when an agent needs one retrieval tool that starts with cheap
HTTP/document extraction and can fall back to a browser only when explicitly
allowed:

```elixir
{:ok, result} =
  Jido.Browser.fetch_rich(
    "https://example.com/protected-docs",
    http_backends: [:req],
    browser_fallback: true,
    pool: :default,
    citations: true
  )

result.retrieval_path # :web_fetch or :browser
result.blocked?
result.content
```

`fetch_rich/2` returns the same core result shape as `web_fetch/2` and adds
`retrieval_path`, `fallback_reason`, and `blocked?`. `web_fetch/2` remains
stateless and never uses pools.

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
`Jido.Browser.Adapters.Lightpanda`.

- AgentBrowser pools keep full warm daemon-backed sessions ready for checkout.
- Lightpanda pools keep prestarted Lightpanda/CDP sessions ready for checkout.
- `lifecycle: :ephemeral` is the default: `end_session/1` recycles the checked-out
  worker and warms a replacement in the background.
- `lifecycle: :persistent` returns healthy workers to the pool after normal
  `end_session/1`; owner crashes, failed health checks, `max_uses`, and
  `max_age_ms` still recycle workers.

Inspect a pool with:

```elixir
{:ok, status} = Jido.Browser.pool_status(:default)

status.ready
status.leased
status.lifecycle
```

Persistent pools can preserve browser profile continuity, cookies, storage, and
session history for application-managed workflows. They do not guarantee access
through bot filters; egress, traffic rate, target-site policy, and user-provided
state remain application concerns.

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

config :jido_browser, :lightpanda,
  binary_path: "/usr/local/bin/lightpanda",
  disable_telemetry: true
```

Optional web fetch settings:

```elixir
config :jido_browser, :web_fetch,
  backend: Jido.Browser.WebFetch.Backends.Req,
  cache_ttl_ms: 300_000,
  max_response_bytes: 5 * 1024 * 1024,
  req: [
    connect_options: [
      timeout: 10_000
    ]
  ],
  extractous: [
    pdf: [extract_annotation_text: true],
    office: [include_headers_and_footers: true]
  ]
```

Configured `req` and `extractous` options are merged with any per-call options
passed to `Jido.Browser.web_fetch/2`. Extractous options apply only when the host
application includes the optional `extractous_ex` dependency. The top-level
`max_response_bytes` value is authoritative for the built-in Req backend.

## Backends

### AgentBrowser (Default)

- native snapshot support with refs
- supervised daemon per session
- optional warm session pools with explicit checkout
- direct JSON IPC from Elixir
- built-in state save/load and tab management support

### Lightpanda (Limited)

- optional adapter backed by `light_cdp`
- supports session lifecycle, navigation, click, type, PNG screenshots, content extraction, and JavaScript evaluation
- supports warm pools for prestarted Lightpanda/CDP sessions
- uses `lightpanda_ex` for pinned Lightpanda binary installation
- disables Lightpanda telemetry by default with `LIGHTPANDA_DISABLE_TELEMETRY=true`
- does not provide AgentBrowser-native refs, state persistence, tab management, or console capture

### Vibium

- CLI-backed browser sessions without warm-pool support
- navigation, click, type, PNG screenshots, content extraction, and JavaScript evaluation

### Migrating from the removed Web adapter

Jido Browser 3.0 removes `Jido.Browser.Adapters.Web`, its `:web`
configuration, and the `mix jido_browser.install web` target.

- Use `Jido.Browser.Adapters.AgentBrowser` for stateful sessions, rendered
  pages, JavaScript, and warm pools.
- Use `Jido.Browser.web_fetch/2` with the default
  `Jido.Browser.WebFetch.Backends.Req` backend for stateless HTTP retrieval.

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

`Jido.Browser.Plugin` is the core tool profile. It includes 20 actions for
normal navigation, interaction, waits, page reading, screenshots, web fetches,
and session close operations. Use `Jido.Browser.Plugin.Debug` to add status and
live page diagnostics.

Existing users who need every browser action can use the All plugin:

```elixir
defmodule MyFullBrowsingAgent do
  use Jido.Agent,
    name: "full_web_browser",
    plugins: [{Jido.Browser.Plugin.All, [headless: true]}]
end
```

`Jido.Browser.Plugin.All` restores all 40 actions, including browser state, element
queries, tab management, diagnostics, JavaScript evaluation, and stateless web
fetch.

## License

Apache-2.0 - See [LICENSE](LICENSE) for details.
