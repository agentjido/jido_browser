# AGENTS.md - Jido.Browser Guide

## Intent
Expose browser automation as session-scoped Jido actions with predictable adapter behavior.

## Runtime Baseline
- Elixir `~> 1.18`
- OTP `27+` (release QA baseline)

## Commands
- `mix test`
- `mix q` or `mix quality` (`compile --warnings-as-errors`, `format --check-formatted`, `credo --strict`, `dialyzer`, `doctor --raise`)
- `mix coveralls.html`
- `mix docs`
- `mix jido_browser.install --if-missing` before integration runs on fresh environments

## Architecture Snapshot
- `Jido.Browser`: public API for session lifecycle + browser operations
- `Jido.Browser.Session`: session state/schema
- `Jido.Browser.Adapter`: behavior for backend adapters
- Adapters: `Jido.Browser.Adapters.Vibium` (default), `Jido.Browser.Adapters.Web`
- `Jido.Browser.Plugin`: bundles browser actions for agent integration
- `Jido.Browser.Actions.*`: navigation, interaction, wait/query, snapshot/screenshot/extraction

## Standards
- Pass session/tool context explicitly; avoid hidden global session state
- Keep adapter differences behind `Jido.Browser.Adapter` behavior boundaries
- Use **Zoi-first** schemas for new structures/actions and keep error contracts explicit
- Return stable tagged tuples from action APIs (`{:ok, ...}` / `{:error, ...}`)

## Testing and QA
- Cover both adapter contract correctness and action-level behavior
- Mark expected noisy integration tests with `@tag capture_log: true` when needed
- Prefer robust selectors and explicit wait conditions to reduce flakiness

## Release Hygiene
- Keep semver ranges stable (`~> 2.0` for `jido_browser`, `~> 2.0` peers)
- Use Conventional Commits
- Update `CHANGELOG.md` and docs when adapter/action behavior changes

## References
- `README.md`
- `usage-rules.md`
- `lib/jido_browser/actions/`
- https://hexdocs.pm/jido_browser
