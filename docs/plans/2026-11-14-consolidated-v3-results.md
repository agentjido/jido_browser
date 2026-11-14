# Browser local upgrade results

Date: 2026-11-14. Owner: U1. Integration owner: Jidoka coordinator.

## Source state

- Path: `/Users/mhostetler/Source/Jido/jido_adapters/jido_browser`.
- Origin: `git@github.com:agentjido/jido_browser.git`.
- Branch: `upgrade/consolidated-v3`.
- HEAD and release baseline: `af5348c0f3e6e23c0ee1f1371e4210240630d3e2`.
- Core source: `agentjido/jido`, exact revision `05723b96c6ead47dec04fe69b1c34ad62f999c54`. Verified in the installed dependency checkout.
- Toolchain: Elixir 1.20.4, Erlang/OTP 29.1.2.
- No commit, push, PR, release, core edit, or live backend installation was made. The earlier plan was preserved. Only assignment files changed.

## Changes

The manifest and lock now use consolidated Jido, registry Zoi 0.19.0, and the core's registry Runic 0.1.0-alpha.13. Split core dependencies, the Zoi fork, and the moving Runic main override were removed. ReqLLM 1.30.0 and the new core dependency closure were resolved.

Browser IDs now use `Jido.Id.uuid7/0`. The plugin state schema uses `Jido.Joi.object/1`, which preserves fields and passes target stored-state validation. Field names and initial values remain the same. Tests use current error types and public plugin initialization instead of the removed `runtime_plugins/1` helper.

The added `test/jido_browser/consolidated_jido_test.exs` runs StartSession, Navigate, GetTitle, and EndSession through `Jido.Exec`. It also checks validation failure and a declared Agent route with `state :unchanged`. The test adapter requires no real browser. Docs use the supported `plugins:` declaration and describe the consolidated source.

No automatic action-route registration, result reducer, session persistence, or second runtime was added. Hosts still select actions from the registry and pass sessions explicitly. Existing backend removals from release/v3 remain in place.

## Checks

All commands ran from the package root.

| Command | Exit | Result |
| --- | --- | --- |
| `mix deps.update zoi runic req_llm splode nimble_options` | 0 | Required core closure resolved. |
| `mix deps.get` | 0 | Exact Git core and registry dependencies installed. |
| `mix compile --warnings-as-errors` | 0 | Package compiled against the exact target. |
| Focused test command below | 0 | 86 tests passed. |
| `mix test` | 0 | 400 tests passed; 20 integration tests excluded by the helper. |
| `mix quality` | 0 | Compile, format, strict Credo, Dialyzer, and Doctor passed. |
| `mix deps.tree` | 0 | No split core application. |
| `git diff --check` | 0 | No whitespace error. |

Exact focused command:

```sh
mix test test/jido_browser/consolidated_jido_test.exs test/jido_browser/plugin_test.exs test/jido_browser/action_contract_lifecycle_navigation_test.exs test/jido_browser/action_contract_interaction_query_test.exs test/jido_browser/action_contract_content_composite_test.exs test/jido_browser/schema_test.exs test/jido_browser/id_test.exs
```

The full suite includes fake binary and installer tests. Printed installer messages do not indicate a live backend installation. No excluded live integration test was counted as a pass.

The active dev compile paths contain exactly one copy of each checked module: `Jido`, `Jido.Action`, `Jido.Signal`, and `Jido.AI`, all under the `jido` application. No temporary path, split provider, or Zoi fork is used.

Logs: `/tmp/u1-jido_browser-compile.log`, `/tmp/u1-browser-focused.log`, `/tmp/u1-jido_browser-test.log`, `/tmp/u1-jido_browser-quality.log`, and `/tmp/u1-jido_browser-tree.log`.

## Return

The local package is ready for Jidoka compile and deterministic integration checks. There is no package blocker. Jidoka capability discovery and tool execution, live AgentBrowser, Lightpanda, Vibium, and optional Extractous integration were not tested here. Existing stored browser sessions were not converted or tested.

See the [source audit and plan](2026-11-14-consolidated-v3-upgrade.md). The coordinator authorized local implementation after that planning phase.
