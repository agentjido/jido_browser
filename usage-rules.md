# Jido Browser Usage Rules

## Intent
Use browser automation as explicit, session-scoped actions that are safe for agent/tool execution.

## Core Contracts
- Start a session before interaction and always end it.
- Pass session context explicitly (`tool_context.session` or equivalent).
- Keep selectors resilient and pair interactions with explicit wait conditions.
- Keep adapter-specific behavior behind the `JidoBrowser.Adapter` contract.
- Preserve stable tagged tuple results and typed errors.

## Library Author Patterns
- Build browser actions as single-purpose primitives (navigate, click, type, extract).
- Add higher-level workflows by composing actions in agents/plans, not by inflating one action.
- Keep screenshot/snapshot/content extraction paths deterministic for AI consumption.
- Validate action params with clear schema constraints.

## QA Patterns
- Cover both adapters for contract-level behavior.
- Mark known noisy integration tests with `@tag capture_log: true` when necessary.
- Run install/setup checks (`mix jido_browser.install --if-missing`) in CI smoke flows.

## Avoid
- Hidden global browser session state.
- Hardcoded brittle selectors without wait/retry semantics.
- Long-running sessions without lifecycle cleanup.

## References
- `README.md`
- `AGENTS.md`
- `lib/jido_browser/actions/`
- https://hexdocs.pm/jido_browser
- https://hexdocs.pm/usage_rules/readme.html#usage-rules
