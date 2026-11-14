# Jido Browser consolidated Jido V3 upgrade plan

Date: 2026-11-14. Assignment: U1, Browser. Status: checked source plan; implementation is not started.

## Authority and boundary

This plan permits no implementation, dependency installation, branch switch, commit, push, PR, external browser installation, or release. The coordinator owns Jidoka integration. Preserve unrelated work. Do not edit `CHANGELOG.md`.

This is a breaking consumer migration to one consolidated `:jido` application. No split core applications or duplicate core modules may remain. No core change is proposed or authorized. Browser action profiles and backend differences remain package-owned.

## Recorded sources and baseline

Before this plan write, the local origin was `git@github.com:agentjido/jido_browser.git`, branch `main`, HEAD `3c56eb042e0d3ecbfa80ea494ee3dbeb1e4a83b0`. `git status --short` was empty. No `docs/ROLE.md` was present. Read workspace and package instructions, including the release instruction difference: the release uses V3 prerelease constraints and removes the Web adapter from its architecture list.

GitHub `release/v3` and local `origin/release/v3` both resolve to `af5348c0f3e6e23c0ee1f1371e4210240630d3e2`. **Use this exact release commit as the implementation baseline**, on a new work branch after authorization. The main-to-release comparison covers 160 files, with 3,899 additions and 6,372 deletions. The release adds static action profiles, action and result contracts, schema helpers, and V3 plugin callbacks. It removes the old Web adapter and vendored Browsey transport. Preserve these release changes; do not reintroduce removed backends from main.

Use the shared Jido revision `05723b96c6ead47dec04fe69b1c34ad62f999c54`, version `3.0.0-beta.2`. It declares Zoi `~> 0.19.0`, ReqLLM `~> 1.30`, and Runic `~> 0.1.0-alpha.13`. Its exact Git object was inspected from an archive. The older local Jido HEAD `15698ccc2f644bfab0c18433a594049c3a16fa9a` was not used as target evidence.

The Browser release lock selects Jido `21d0dd4c4da2f9c096fbd1cec9ad1d22dce95e61`, split Action `177e7a4ce4342a9a6b7bc668f540dafbd7169d54`, split Signal `7b825f1d050a0e0159bb2a72ba79c100b5d362d3`, moving Runic main at `0c15a9c107137b8c13ebbc3340abd207d8f1f3ff`, and the Zoi fork ref `2fff2a23e23e7ac0b26f62f49bbc1b12f7818ac9`. None proves compatibility with the shared target.

## Required file and API changes

| Release files | Source finding and required work |
| --- | --- |
| `mix.exs`, `mix.lock` | Pin consolidated Jido to the exact shared ref. Remove split Action and Signal declarations. Remove the direct Runic main override; Browser runtime has no need to choose the core execution engine source. Replace the Zoi fork with registry `~> 0.19.0`. Resolve the target closure without unrelated upgrades. |
| `lib/jido_browser/action.ex` | Target `Jido.Action` retains `on_before_validate_params/1`, static schemas, and `run/2`. Preserve unknown-key behavior only where intended. Check the custom default injection against Joi parsing; defaults must not be applied twice or change explicit supplied values. Prefer public Joi behavior when tests prove the same contract. Do not assume direct `%Zoi.Types.Map{}` internals are stable without the 0.19 checks. |
| `lib/jido_browser/schema.ex`, `zoi_json_schema.ex`, action schemas, Session and Lease schemas | Verify string tool input to atom enum conversion, atom JSON Schema output, nullable values, defaults, required lists, and output validation with registry Zoi 0.19. The upstream v0.19.0 Enum source has mapping and coercion plus a JSON Schema encoder. Its Atom source has no JSON Schema encoder; Browser currently supplies one. Keep the Browser encoder unless a resolved version already supplies it, then remove only the duplicate implementation. No fork is assumed necessary. |
| `test/support/action_contract_assertions.ex` | Replace `%Jido.Action.Error.InvalidInputError{}` with `%Jido.Error.ValidationError{}`. The old error module is absent. Check the public Exec validation boundary as well as direct action validation. |
| `test/jido_browser/plugin_test.exs` | Replace removed `Jido.Signal.ID.generate!()` with `Jido.Id.uuid7()`. Replace removed `Jido.Agent.runtime_plugins/1` with declarations from `Jido.Agent.definition(agent).plugins` for any necessary normalizer assertion. Prefer public Agent instantiation and behavior tests over tests of internal normalization. `Jido.Agent.instantiate/2` and `Jido.Plugin.Normalizer.normalize_all/1` still exist. |
| `lib/jido_browser/plugin/profile.ex`, `plugin/agent.ex` | Target `Jido.Plugin` supports `vsn`, `option_keys`, `state_spec/1`, `prepare/2`, and `reduce/2`. Existing callback signatures and `plugin_state` fields match. Keep one `:browser` state owner. Verify all three static profiles and supplied options under target checked state initialization. No Agent facet split or extra runtime process is required. |
| `lib/jido_browser/plugin.ex`, `plugin/debug.ex`, `plugin/all.ex`, `action_registry.ex` | The target Plugin behavior does not invoke legacy `mount/2`, `handle_signal/2`, `transform_result/3`, `actions/0`, `signal_routes/0`, or `plugin_spec/1` as automatic hooks. Keep useful public helpers, but document their caller ownership. Existing `state_spec/1` explicitly calls mount, so initial state still has a path. Existing reduce is a no-op; it does not apply transform_result state updates. Do not claim that plugin installation runs actions, routes signals, owns session cleanup, or updates browser state automatically. |
| `README.md`, `guides/migration_3_0.md`, `guides/release_preparation.md`, `usage-rules.md`, plugin moduledocs | Replace obsolete `agent do plugin ... end` examples with target `plugins:` declarations. Show explicit action invocation and authored routes where needed. Mark the metadata action and signal lists as caller inputs. State the backend and profile removals already made on release/v3. |

Zoi schemas remain valid Joi schema values in the target. A full rename of every Zoi call is unnecessary. Target `Jido.Joi` adds checked state and JSON Schema policies; use it where the core contract is required, with focused tests for any behavior change.

## Action, signal, and plugin proof

Keep `Jido.Browser.Adapters.Test` as the deterministic adapter. Run StartSession, Navigate, GetTitle or Snapshot, and EndSession through `Jido.Exec.run/4`. Prove input coercion, output shape, unknown keys, and error normalization. Check direct adapter calls separately from Exec calls; a direct action `run/2` does not validate its boundaries.

Add one explicit test Agent using `plugins: [{Jido.Browser.Plugin, %{adapter: Jido.Browser.Adapters.Test}}]`. Use target authored `routes do route ... end` for a selected browser action and select `state :unchanged` where output is a browser result rather than the complete Agent state. Deliver a `Jido.Signal.new/1` value through `Jido.Agent.cmd/3`. Prove that no undeclared route appears merely from `signal_routes/0` metadata. Keep Browser action discovery through `ActionRegistry` available to hosts such as Jidoka.

Do not add a second runtime or invent a core automatic action-provider contract. If Jidoka requires automatic profile route installation or result-to-owned-state reduction, the integration owner must select explicit host routes or a package-owned adapter using supported extension APIs. That requirement is not proved by current metadata tests. Report a required unsupported behavior before implementation beyond this bounded plan. The initial migration can preserve the existing helper API without promising automatic behavior.

Live Session values can contain adapter state or processes. Do not add persistence dump/load callbacks or claim portable browser sessions in this unit. Stored-data migration is outside scope.

## Unit order and source strategy

1. Prepare the exact release baseline after authorization. Record branch, HEAD, origin, and changes again.
2. Resolve the single-core graph with registry Zoi 0.19. Remove the Runic source override and split providers.
3. Repair removed test APIs. Check schema contracts and actions with the deterministic adapter.
4. Check plugin initialization, explicit routes, caller-owned metadata, and all static profiles. Update docs to match proved behavior.
5. Run package checks and portable resolution. Return the checked candidate to the coordinator for Jidoka tool discovery and runtime integration.

Ash and Browser do not depend on one another. Both depend on the same target Jido. If a later release is authorized, order is Jido, Browser, then Jidoka. No backend or ecosystem-wide release is part of this plan.

Local trial: temporarily select an isolated Jido path whose HEAD is exactly `05723b96c6ead47dec04fe69b1c34ad62f999c54`; record its status. Do not use the older sibling working tree. Use separate build and dependency directories. Remove temporary paths before portable checks.

Portable check: use `{:jido, github: "agentjido/jido", ref: "05723b96c6ead47dec04fe69b1c34ad62f999c54"}` and `{:zoi, "~> 0.19.0"}`. Retain an override only for a demonstrated graph need. Regenerate the changed closure only. Do not retain forked Zoi, moving Runic main, or stale split lock entries. A clean portable resolve must get the same selected core source without local paths. Later Hex release constraints need separate proof of the same compatible contract.

## Exact future checks

The release manifest and test paths support these commands. No command below was run during planning. Use Elixir `~> 1.18` and OTP 27 or later, as package instructions require.

```sh
mix deps.get
mix deps.tree
mix compile --warnings-as-errors
mix test test/jido_browser/schema_test.exs test/jido_browser/session_test.exs test/jido_browser/result_test.exs test/jido_browser/error_test.exs test/jido_browser/action_registry_test.exs
mix test test/jido_browser/action_contract_lifecycle_navigation_test.exs test/jido_browser/action_contract_interaction_query_test.exs test/jido_browser/action_contract_content_composite_test.exs
mix test test/jido_browser/plugin_test.exs test/jido_browser/actions_test.exs test/jido_browser/adapters/contract_test.exs
mix test
mix quality
```

Add the Exec action sequence and explicit Agent route tests to `test/jido_browser/plugin_test.exs` or a focused adjacent file. If a new path is used, add its exact command to the execution return. The default test helper excludes `:integration`. Therefore `mix test` does not prove installed backend compatibility.

When live backend verification is separately authorized and binaries are available:

```sh
mix jido_browser.install --if-missing
mix test --include integration test/jido_browser/adapters/agent_browser_smoke_test.exs test/jido_browser/adapters/agent_browser_integration_test.exs
mix test --include integration test/jido_browser/adapters/lightpanda_integration_test.exs test/jido_browser/adapters/vibium_integration_test.exs
```

Report missing backend binaries as a limit for the exact affected check. Do not count a test skip as success. These integration checks are additional backend evidence; deterministic Jido boundary tests remain required.

Repeat compile and focused tests with portable sources in a clean environment. Review the lock, dependency tree, and compile paths for exactly one provider of core, Action, Signal, and AI modules. No split application may remain, even if dependency overrides suppress conflicts. `mix quality` runs warnings-as-errors compile, format check, strict Credo, Dialyzer, and Doctor. The release manifest selects the test environment for this alias.

## Readiness, blockers, and coverage

**Verdict: ready for a bounded implementation; not compatible as currently declared.** Required target APIs exist for Action, Exec, schemas, Signal construction, Plugin callbacks, and explicit Agent routes. No core change is needed for these checks. Automatic profile execution and result reduction are not current core contracts; do not promise them without explicit caller wiring and proof.

First safe implementation unit: prepare the recorded release baseline, replace dependency sources, remove split providers and Runic main, and repair removed test APIs. Compile and run schema, action, and plugin initialization tests. Then add the deterministic Exec action sequence. Keep automatic route installation and result reduction outside this first unit. Wait for the coordinator's bounded assignment before this unit starts.

No build, test, quality check, dependency install, backend install, or live browser run occurred. Affected but untested consumers: Jidoka capability discovery and tool execution, host Agents that used old automatic plugin assumptions, AgentBrowser, Lightpanda, Vibium, and optional Extractous integration. Other ecosystem consumers were not inventoried or tested. Web and Browsey are already removed on the selected baseline and are not supported by this migration.

## Source index

- [Canonical coordinator plan](../../../../docs/plans/2026-11-14-0821-jidoka-consolidated-v3-plan.md).
- [Browser release source](https://github.com/agentjido/jido_browser/tree/af5348c0f3e6e23c0ee1f1371e4210240630d3e2): manifests, lock, files and tests named above, and `test/test_helper.exs`.
- [Target Jido source](https://github.com/agentjido/jido/tree/05723b96c6ead47dec04fe69b1c34ad62f999c54): `mix.exs`, `lib/jido/action.ex`, `lib/jido/error.ex`, `lib/jido/exec.ex`, `lib/jido/joi.ex`, `lib/jido/id.ex`, `lib/jido/plugin.ex`, `lib/jido/plugin/spec.ex`, `lib/jido/plugin/normalizer.ex`, `lib/jido/agent.ex`, `lib/jido/agent/plugin/preparation.ex`, and `lib/jido/agent/plugin/reduction.ex`.
- [Zoi 0.19 enum source](https://github.com/phcurado/zoi/blob/v0.19.0/lib/zoi/types/enum.ex) and [Atom source](https://github.com/phcurado/zoi/blob/v0.19.0/lib/zoi/types/atom.ex), read through `gh api`.
- Jidoka source inspected read-only: `mix.exs` and `lib/jidoka/capabilities/catalog.ex`.
