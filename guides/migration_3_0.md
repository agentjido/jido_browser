# Migrate Jido Browser 2.x to 3.0

Jido Browser 3.0 removes deprecated adapters and makes its Action, result,
error, identifier, and tool contracts explicit. This guide lists each required
application change.

Jido Browser 3.0 is not published. Use the `v3` branch only for integration
testing. Do not use it as a Hex dependency in a released application.

<!--
BLOCKED BY #77: Replace this comment with the exact released Jido, Jido Action,
Jido Signal, Elixir, and OTP requirements. Recheck all plugin profile examples
against the released Jido compiler before this guide is merged.
-->

## Migration checklist

- Convert custom Action input and output schemas to static Zoi objects.
- Read browser catalog metadata from `Jido.Browser.ActionRegistry`.
- Replace the removed Web adapter with AgentBrowser or WebFetch.
- Replace the removed Browsey backend with Req or a real-browser fallback.
- Change successful result access from string keys to atom keys.
- Match explicit browser exceptions instead of Splode-generated error classes.
- Treat browser-generated identifiers as opaque UUIDv7 strings.
- Add ExtractousEx directly if the application reads PDF or office documents.
- Use `Jido.Browser.Plugin.All` if an existing agent needs all 40 browser actions.
- Update Jido ecosystem dependencies and the Elixir requirement after #77 is
  complete.

## Use static Zoi Action schemas

Issues [#76](https://github.com/agentjido/jido_browser/issues/76) and
[#91](https://github.com/agentjido/jido_browser/issues/91) replace keyword-list
input schemas and implicit output contracts with static Zoi schemas.

### Input schemas

Before:

```elixir
use Jido.Action,
  name: "read_browser_page",
  schema: [
    url: [type: :string, required: true, doc: "URL to read"],
    format: [type: {:in, [:markdown, :text]}, default: :markdown]
  ]
```

After:

```elixir
use Jido.Action,
  name: "read_browser_page",
  schema:
    Zoi.object(%{
      url: Zoi.string(description: "URL to read"),
      format:
        Zoi.enum([:markdown, :text], description: "Output format")
        |> Zoi.default(:markdown)
    })
```

All 40 browser actions now return a Zoi value from `schema/0`. Required fields,
optional fields, defaults, enum values, and descriptions stay part of the
contract. Code that reads the old keyword-list representation must use Zoi
functions instead.

### Output schemas

Each browser action now returns a static Zoi value from `output_schema/0`.
Applications can validate a result at an Action boundary:

```elixir
result = %{
  status: "success",
  url: "https://example.com",
  content: "Example page",
  format: :markdown,
  metadata: %{}
}

{:ok, validated} = Jido.Browser.Actions.ReadPage.validate_output(result)
```

The output schemas require stable top-level fields and their public types.
They keep unknown top-level fields because Jido Action preserves values outside
the declared schema. Values under `:result`, `:metadata`, and `:raw` remain
opaque.

## Read browser metadata from the registry

Issue [#78](https://github.com/agentjido/jido_browser/issues/78) moves
browser-owned catalog data out of the Action modules.

Before:

```elixir
action = Jido.Browser.Actions.Navigate

category = action.category()
tags = action.tags()
version = action.vsn()
```

After:

```elixir
action = Jido.Browser.Actions.Navigate

{:ok, entry} = Jido.Browser.ActionRegistry.fetch(action)

category = entry.category
tags = entry.tags
version = entry.tool_contract_version
```

The following Action functions are removed:

- `category/0`
- `tags/0`
- `vsn/0`

Use these registry functions for discovery:

- `entries/0` returns all entries in stable order.
- `fetch/1` accepts an Action module or signal name.
- `by_category/1`, `with_tag/1`, and `by_support_level/1` filter entries.
- `tool_contract_version/0` returns the browser tool contract version.

## Replace removed adapters and backends

Issues [#80](https://github.com/agentjido/jido_browser/issues/80) and
[#81](https://github.com/agentjido/jido_browser/issues/81) remove the deprecated
Web adapter and the bundled BrowseyHttp runtime.

### Stateful browser work

Use AgentBrowser when a task needs a rendered page, JavaScript, browser state,
or a warm browser pool.

Before:

```elixir
config :jido_browser, :web,
  binary_path: "/path/to/web"

{:ok, session} =
  Jido.Browser.start_session(adapter: Jido.Browser.Adapters.Web)
```

After:

```elixir
config :jido_browser, :agent_browser,
  binary_path: "/path/to/agent-browser"

{:ok, session} =
  Jido.Browser.start_session(adapter: Jido.Browser.Adapters.AgentBrowser)
```

These modules and installer target are removed:

- `Jido.Browser.Adapters.Web`
- `Jido.Browser.Adapters.Web.CLI`
- `Jido.Browser.Adapters.Web.PoolRuntime`
- `mix jido_browser.install web`

Install AgentBrowser instead:

```sh
mix jido_browser.install agent_browser
```

### Stateless HTTP retrieval

Use the Req backend when the task does not need browser rendering.

Before:

```elixir
config :jido_browser, :web_fetch,
  backend: :browsey,
  browsey: [binary_path: "/path/to/curl-impersonate"]

{:ok, result} = Jido.Browser.web_fetch("https://example.com", backend: :browsey)
```

After:

```elixir
config :jido_browser, :web_fetch,
  backend: :req

{:ok, result} = Jido.Browser.web_fetch("https://example.com", backend: :req)
```

The `:browsey` alias, `Jido.Browser.WebFetch.Backends.Browsey`, `browsey:`
configuration, vendored BrowseyHttp source, and curl-impersonate binaries are
removed.

Use `fetch_rich/2` when the application normally uses HTTP but can fall back to
a real browser:

```elixir
{:ok, result} =
  Jido.Browser.fetch_rich("https://example.com",
    backend: :req,
    browser_fallback: true,
    adapter: Jido.Browser.Adapters.AgentBrowser
  )
```

## Use atom-key public results

Issue [#82](https://github.com/agentjido/jido_browser/issues/82) gives every
supported adapter one public Elixir key style.

Before:

```elixir
tab_id = result["tabId"]
title = result["title"]
```

After:

```elixir
tab_id = result.tab_id
title = result.title
```

The public result rules are:

- Stable public map keys are atoms.
- Upstream camel-case fields use snake-case atom keys. For example, `tabId`
  becomes `:tab_id`.
- Nested tab, element, and reference metadata also use atom keys.
- Dynamic reference identifiers, such as `"@e1"`, stay strings.
- Unknown upstream protocol fields are stored under `:raw`.
- Values under `:result`, `:metadata`, and `:raw` keep their source key style.

Tagged tuples do not change. Successful stateful calls still return
`{:ok, session, result}`, and failures still return `{:error, reason}`.

Custom adapters must return atom-key public result maps.

## Match explicit browser exceptions

Issue [#83](https://github.com/agentjido/jido_browser/issues/83) removes the
browser package's Splode-generated error hierarchy.

Match the concrete exception in the normal tagged result:

```elixir
case Jido.Browser.navigate(session, url) do
  {:ok, updated_session, result} ->
    {:ok, updated_session, result}

  {:error, %Jido.Browser.Error.NavigationError{} = error} ->
    {:error, error}

  {:error, %Jido.Browser.Error.TimeoutError{} = error} ->
    {:error, error}
end
```

The stable exception modules are:

- `Jido.Browser.Error.AdapterError`
- `Jido.Browser.Error.NavigationError`
- `Jido.Browser.Error.ElementError`
- `Jido.Browser.Error.TimeoutError`
- `Jido.Browser.Error.EvaluationError`
- `Jido.Browser.Error.InvalidError`
- `Jido.Browser.Error.InternalError`

`InternalError` represents unexpected browser-internal failures.

The generated class modules `Invalid`, `Adapter`, `Navigation`, `Element`,
`Timeout`, `Unknown`, and `Unknown.UnknownError` are removed. The following
Splode normalization helpers are also removed from `Jido.Browser.Error`:

- `from_json`
- `set_path`
- `splode_error?`
- `to_class`
- `to_error`
- `traverse_errors`
- `unwrap!`

Public error details remove credentials, request and response data, scripts,
URL credentials and query values, and sensitive selectors.

## Treat browser identifiers as opaque

Issue [#84](https://github.com/agentjido/jido_browser/issues/84) routes all
browser-generated identifiers through `Jido.generate_id/0`.

Generated session, runtime, request, lease, and temporary identifiers are now
time-ordered UUIDv7 strings. Do not validate them as UUIDv4 values or parse
internal integer identifiers.

Before:

```elixir
{:ok, session} = Jido.Browser.start_session()
true = uuid_v4?(session.id)
```

After:

```elixir
{:ok, session} = Jido.Browser.start_session()
true = is_binary(session.id)
```

Caller-provided session IDs and named pool IDs keep their supplied values. The
direct `uniq` dependency is removed from Jido Browser.

## Install document extraction only when needed

Issue [#85](https://github.com/agentjido/jido_browser/issues/85) makes
ExtractousEx optional. Browser automation and HTML or text retrieval no longer
install or start ExtractousEx, Rustler, or a native extraction library.

Applications that read PDF or office documents must add ExtractousEx directly:

```elixir
defp deps do
  [
    {:jido_browser, "~> 3.0"},
    {:extractous_ex, "~> 0.2"}
  ]
end
```

Existing `:extractous` configuration and per-call options still apply when the
optional dependency is installed.

Without ExtractousEx, PDF and office requests return this stable error shape:

```elixir
{:error,
 %Jido.Browser.Error.AdapterError{
   details: %{
     error_code: :unsupported_feature,
     feature: :document_extraction,
     dependency: :extractous_ex
   }
 }}
```

HTML and text retrieval do not use the optional extractor.

## Select a browser tool profile

Issues [#79](https://github.com/agentjido/jido_browser/issues/79) and
[#136](https://github.com/agentjido/jido_browser/issues/136) define three
compiler-static browser plugins.

The profiles are:

- `Jido.Browser.Plugin` provides the 20 core session, navigation, interaction,
  wait, snapshot, screenshot, page reading, and web fetch actions.
- `Jido.Browser.Plugin.Debug` provides the 27 core and diagnostic actions.
- `Jido.Browser.Plugin.All` provides all 40 registered browser actions.

Before:

```elixir
plugins: [{Jido.Browser.Plugin, [profile: :all, headless: true]}]
```

After:

```elixir
defmodule MyFullBrowsingAgent do
  use Jido.Agent,
    name: "full_web_browser",
    plugins: [{Jido.Browser.Plugin.All, [headless: true]}]
end
```

The `profile:` option is removed and rejected. Runtime options such as
`headless:`, `adapter:`, and `pool:` remain plugin configuration. Signal names
do not change. Each plugin preserves registry order for actions, routes, and
signal patterns. Its exact contract and state schema are available to the Jido
compiler as static metadata.

Use the profile-aware registry functions for inspection:

```elixir
profiles = Jido.Browser.ActionRegistry.profiles()
core_actions = Jido.Browser.ActionRegistry.actions(:core)
all_routes = Jido.Browser.ActionRegistry.signal_routes(:all)
```

The arity-zero registry functions still return the complete registry.

## Update the Jido ecosystem

Issue [#77](https://github.com/agentjido/jido_browser/issues/77) will define the
exact Jido, Jido Action, Jido Signal, Elixir, and OTP requirements. This section
must be completed from released packages before this guide is merged.

Do not use `override: true` to combine Jido 2 with Jido Action 3. Do not release
an application against an unpublished Jido branch.
