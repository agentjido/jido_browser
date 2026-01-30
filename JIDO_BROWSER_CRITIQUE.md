# JidoBrowser Code Critique

**Date:** 2026-01-29  
**Version:** 0.1.0  
**Reviewer:** Automated Analysis + Oracle Review

---

## Executive Summary

JidoBrowser is a **well-structured browser automation library** with clean architecture and strong documentation discipline. However, there are **critical issues with session state semantics** and **adapter contract mismatches** that will cause bugs in real-world usage. These should be addressed before production use.

| Metric | Status | Details |
|--------|--------|---------|
| Tests | ✅ 92 passing | 0 failures, 11 excluded (integration) |
| Coverage | ⚠️ 41.7% | Adapters at 0% (require real binaries) |
| Credo | ⚠️ 1 issue | Cyclomatic complexity in `detect_platform` |
| Dialyzer | ✅ Passing | No type errors |
| Doctor | ✅ 100% | Full doc and spec coverage |

**Priority fixes needed:** Session state semantics, adapter contract alignment, replace raises with error tuples.

---

## Architecture Review

### Strengths

1. **Clean Adapter Pattern**: The `JidoBrowser.Adapter` behaviour provides a solid seam for supporting multiple backends (Vibium, Web, future adapters).

2. **Action-per-Capability Design**: 26 discrete `Jido.Action` modules make capabilities discoverable, schema-validated, and composable for AI agents.

3. **Skill Integration**: `JidoBrowser.Skill` cleanly wraps session lifecycle, provides a router with `browser.*` patterns, and includes error diagnostics enhancement.

4. **Error Taxonomy**: `JidoBrowser.Error` uses Splode effectively for error classification (Invalid, Adapter, Navigation, Element, Timeout).

5. **Schema Validation**: Zoi for Session struct validation, NimbleOptions schemas for action parameters.

### Concerns

1. **Stateless CLI Per-Operation**: Each adapter operation spawns a new Port/process. Simple but has overhead for high-throughput scenarios.

2. **No Process Ownership of Sessions**: Sessions are pure data with no GenServer backing. This simplifies code but makes resource cleanup and state management the caller's responsibility.

---

## Critical Issues

### 1. Session State Semantics Are Broken (MAJOR)

**Location:** `lib/jido_browser/adapters/vibium.ex`

The Vibium adapter stores `current_url` in the session's connection, but Elixir data is immutable. The adapter returns an updated session nested inside the result:

```elixir
# navigate/3 returns:
{:ok, %{url: url, output: output, session: updated_session}}
```

But subsequent operations do:

```elixir
url = connection.current_url || raise "No current URL - navigate first"
```

**Problem:** The caller's original `session` variable is never mutated. Unless Actions explicitly extract and persist `result.session`, all subsequent calls will raise even after successful navigation.

**Current Actions don't update session**, so this will fail in real usage:

```elixir
{:ok, session} = JidoBrowser.start_session()
{:ok, _} = JidoBrowser.navigate(session, "https://example.com")  # Returns updated session in result
{:ok, _} = JidoBrowser.click(session, "button")  # RAISES: "No current URL - navigate first"
```

**Fix Options:**
- **Option A (Recommended):** Make `navigate/3` return the updated session at top level: `{:ok, %Session{}, %{url: url, ...}}`
- **Option B:** Don't require URL in adapter operations; query `window.location.href` when needed
- **Option C:** Store URL in adapter process state (requires GenServer)

---

### 2. Adapter Contract Mismatches (MAJOR)

**Location:** `lib/jido_browser/adapters/vibium.ex`

| Method | Documented Behavior | Actual Behavior |
|--------|---------------------|-----------------|
| `extract_content/2` | Respects `:format` option (`:html`/`:markdown`) | Ignores format, returns `format: :text` |
| `screenshot/2` | Supports `:full_page`, `:format` options | Ignores both, always PNG |
| `evaluate/3` | Returns structured Elixir terms | Returns raw string from clicker output |

**Impact:** 
- `Snapshot` action expects `evaluate` to return a map, but gets a string
- `ExtractContent` with `format: :html` is silently ignored
- Tests pass because they mock the facade, hiding adapter drift

**Fix:** Either parse clicker JSON output in adapter, or document string-only returns.

---

### 3. Raises in Library Code (MEDIUM)

**Locations:**
- `lib/jido_browser/adapters/vibium.ex:78,94,108,134,151` - `raise "No current URL..."`
- `lib/jido_browser/adapters/web.ex:75,91,107,134,149` - Same pattern
- All actions' `get_session/1` helper - `raise "No browser session..."`

**Problem:** Raises crash the caller's process. Agent/tooling libraries should return `{:error, reason}` so agents can recover.

**Fix:** Return structured errors:
```elixir
# Instead of:
url = connection.current_url || raise "No current URL - navigate first"

# Do:
case connection.current_url do
  nil -> {:error, Error.navigation_error(nil, :no_current_url)}
  url -> # continue...
end
```

---

### 4. Error Enrichment May Corrupt Exception Structs (MEDIUM)

**Location:** `lib/jido_browser/skill.ex:178-191`

```elixir
enhanced_error = Map.merge(
  if(is_map(error), do: error, else: %{error: error}),
  %{diagnostics: diagnostics}
)
```

Since exceptions are structs (maps), this merges extra keys into them. This can:
- Break pattern matching on `%Error.NavigationError{}`
- Cause issues with struct serialization

**Fix:** Use the exception's existing `:details` field or return a wrapper:
```elixir
{:error, %{error: error, diagnostics: diagnostics}}
```

---

## Performance Issues

### 1. Quadratic String Concatenation (MEDIUM)

**Location:** `lib/jido_browser/adapters/vibium.ex:184`, `lib/jido_browser/adapters/web.ex:200`

```elixir
defp collect_output(port, acc, timeout) do
  receive do
    {^port, {:data, data}} ->
      collect_output(port, acc <> data, timeout)  # O(n) per chunk → O(n²) total
```

For large outputs (page snapshots, extracted content), this becomes slow and memory-heavy.

**Fix:** Use iodata list accumulation:
```elixir
defp collect_output(port, acc, timeout) do
  receive do
    {^port, {:data, data}} ->
      collect_output(port, [acc | data], timeout)
    {^port, {:exit_status, 0}} ->
      {:ok, IO.iodata_to_binary(acc) |> String.trim()}
```

### 2. Per-Operation Port Spawning

Each operation spawns a new OS process. Acceptable for typical usage but will be a bottleneck for high-throughput automation.

---

## Resource Cleanup Issues

### 1. Temp File Leak in Screenshots (LOW)

**Location:** `lib/jido_browser/adapters/vibium.ex:112-129`

```elixir
path = Path.join(System.tmp_dir!(), "jido_browser_#{System.unique_integer()}.png")
# If run_clicker fails, temp file may exist but isn't cleaned up
case run_clicker(connection, args, timeout) do
  {:ok, _output} ->
    case File.read(path) do
      {:ok, bytes} ->
        File.rm(path)  # Only cleaned on success
```

**Fix:** Use `try/after` to ensure cleanup:
```elixir
try do
  # run_clicker and File.read
after
  File.rm(path)
end
```

---

## Test Coverage Analysis

### What's Covered Well

- **Action layer**: All 26 actions have unit tests validating parameter handling and error wrapping
- **Skill metadata**: Configuration, routing, mount lifecycle
- **Session validation**: Zoi schema and new!/1 behavior
- **Error handling paths**: Most error scenarios tested

### Coverage Gaps

| Module | Coverage | Reason |
|--------|----------|--------|
| `Adapters.Vibium` | 0% | Requires real clicker binary |
| `Adapters.Web` | 0% | Requires real web binary |
| `Mix.Tasks.JidoBrowser.Install` | 0% | Platform-specific install task |
| `test/support/test_adapter.ex` | 0% | Test helper, not production code |

### Testing Strategy Issues

1. **No Contract Tests**: Tests mock `JidoBrowser` facade, hiding adapter drift from Actions
2. **Integration Tests Excluded by Default**: Real adapter behavior never verified in CI
3. **Test Adapter Unused**: `JidoBrowser.Adapters.Test` exists but isn't wired into tests

**Recommendations:**
- Add contract tests with `FakeAdapter` returning representative values
- Add CI job that runs `--only integration` when binaries are available
- Use `TestAdapter` for action tests instead of mocking

---

## Code Quality Issues

### 1. Credo Violation

**Location:** `lib/mix/tasks/jido_browser.install.ex:157`

```
Function is too complex (cyclomatic complexity is 10, max is 9)
```

The `detect_platform/0` function has multiple case branches. Easy to refactor into smaller functions.

### 2. Inconsistent Evaluate Arity

- `Adapter` behaviour: `@callback evaluate(session, script, opts)` (3 args)
- Some stub/test code: `JidoBrowser.evaluate(session, script)` (2 args via default opts)
- Actual Vibium impl: 3 args

This works but could cause confusion. Consider making opts non-optional in the behaviour.

### 3. Duplicate `get_session/1` Helper

Every action module has the same helper:
```elixir
defp get_session(context) do
  context[:session] ||
    context[:browser_session] ||
    get_in(context, [:tool_context, :session]) ||
    raise "No browser session in context"
end
```

**Fix:** Move to a shared module like `JidoBrowser.ActionHelpers`.

---

## Security Considerations

### What's Good

- **No shell injection**: Uses `Port.open({:spawn_executable, binary}, args: args)` without shell
- **Password redaction**: Snapshot avoids returning `type=password` field values
- **Scoped extraction**: Snapshot supports `selector` to limit scope

### Areas of Concern

1. **Arbitrary JS Evaluation**: `Evaluate` action allows executing any JavaScript. Fine for local agents but dangerous in multi-tenant systems.

2. **Sensitive Data in Screenshots/Snapshots**: Content may contain secrets. Consider:
   - Documenting that results should be treated as sensitive
   - Adding option to redact additional input types (`token`, `api_key`)

3. **Output Logging**: Ensure extracted content isn't logged by default in agent systems.

---

## Missing Features

For a browser automation library, these will likely be needed soon:

| Feature | Priority | Notes |
|---------|----------|-------|
| Cookie management | High | Export/import for auth persistence |
| File upload/download | Medium | Required for many workflows |
| Network waiting/idle | Medium | Beyond simple selector waits |
| Tab/window management | Low | Multi-tab workflows |
| Auth helpers | Low | Basic auth, header injection |

---

## Documentation Review

### Strengths

- 100% module doc coverage
- Clear Quick Start in README
- Good adapter explanation
- Skill usage documented

### Gaps

1. **No troubleshooting guide** for common issues (binary not found, session errors)
2. **No explanation of session update semantics** (critical given the bug)
3. **Adapter feature matrix** would help users understand capability differences
4. **No architecture diagram** for developers

---

## Recommended Action Plan

### Immediate (Before Production Use)

1. **Fix session state semantics** - Make navigate return session at top level and update Actions to persist it
2. **Align adapter contracts** - Parse JSON output, respect format options, or document limitations
3. **Replace raises with error tuples** - All adapter and action raises should become `{:error, ...}`

### Short Term (Next Sprint)

4. **Fix output collection performance** - Use iodata accumulation
5. **Ensure temp file cleanup** - Use try/after pattern
6. **Add contract tests** - Verify adapter outputs match action expectations
7. **Extract shared `get_session/1`** - DRY up action modules

### Medium Term

8. **Add optional integration tests** - CI with real binaries
9. **Refactor `detect_platform/0`** - Fix Credo complexity issue
10. **Document session semantics** - Add to README and moduledocs
11. **Consider GenServer sessions** - For resource cleanup and state

---

## Summary

JidoBrowser demonstrates **excellent architecture and documentation discipline** but has **critical runtime bugs** that will manifest in real usage:

| Category | Grade | Notes |
|----------|-------|-------|
| Architecture | A- | Clean patterns, minor process model concerns |
| Code Quality | B+ | High discipline, some duplication |
| Test Coverage | C+ | Good action coverage, adapters untested |
| Error Handling | B- | Good structure, raises need fixing |
| Documentation | A | Excellent coverage, missing session semantics |
| Production Readiness | C | Critical session bugs block production use |

**Estimated effort to reach production-ready: 1-2 days**

The foundation is solid. Fix the session semantics, align adapter contracts, and eliminate raises, and this becomes a robust library.
