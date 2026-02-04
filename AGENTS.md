# AGENTS.md - Jido Browser Development Guide

## Build/Test/Lint Commands

- `mix test` - Run tests
- `mix test path/to/specific_test.exs` - Run a single test file
- `mix quality` or `mix q` - Run full quality check (format, compile, dialyzer, credo, doctor)
- `mix format` - Auto-format code
- `mix dialyzer` - Type checking
- `mix credo` - Code analysis
- `mix coveralls` - Test coverage report
- `mix docs` - Generate documentation

## Architecture

JidoBrowser provides browser automation for Jido AI agents using an adapter pattern:

### Core Modules

- **JidoBrowser** - Main API module with session management and browser operations
- **JidoBrowser.Session** - Struct representing an active browser session (Zoi schema)
- **JidoBrowser.Adapter** - Behaviour defining the adapter interface
- **JidoBrowser.Error** - Splode-based error types

### Adapters

- **JidoBrowser.Adapters.Vibium** - Default adapter using Vibium Go binary (WebDriver BiDi)
- **JidoBrowser.Adapters.Web** - Alternative adapter using chrismccord/web CLI

### Plugin

- **JidoBrowser.Plugin** - Jido.Plugin bundling all browser actions with lifecycle management

### Actions (Jido.Action implementations)

**Session Lifecycle:**
- **JidoBrowser.Actions.StartSession** - Start a new browser session
- **JidoBrowser.Actions.EndSession** - End the current session
- **JidoBrowser.Actions.GetStatus** - Get session status

**Navigation:**
- **JidoBrowser.Actions.Navigate** - Navigate to URL
- **JidoBrowser.Actions.Back** - Go back in history
- **JidoBrowser.Actions.Forward** - Go forward in history
- **JidoBrowser.Actions.Reload** - Reload current page
- **JidoBrowser.Actions.GetUrl** - Get current URL
- **JidoBrowser.Actions.GetTitle** - Get page title

**Interaction:**
- **JidoBrowser.Actions.Click** - Click element by selector
- **JidoBrowser.Actions.Type** - Type text into element
- **JidoBrowser.Actions.Hover** - Hover over element
- **JidoBrowser.Actions.Focus** - Focus on element
- **JidoBrowser.Actions.Scroll** - Scroll page or element
- **JidoBrowser.Actions.SelectOption** - Select dropdown option

**Waiting/Synchronization:**
- **JidoBrowser.Actions.Wait** - Wait for specified time
- **JidoBrowser.Actions.WaitForSelector** - Wait for element state
- **JidoBrowser.Actions.WaitForNavigation** - Wait for navigation

**Element Queries:**
- **JidoBrowser.Actions.Query** - Query elements matching selector
- **JidoBrowser.Actions.GetText** - Get element text content
- **JidoBrowser.Actions.GetAttribute** - Get element attribute
- **JidoBrowser.Actions.IsVisible** - Check element visibility

**Content Extraction:**
- **JidoBrowser.Actions.Snapshot** - LLM-optimized page snapshot
- **JidoBrowser.Actions.Screenshot** - Capture screenshot
- **JidoBrowser.Actions.ExtractContent** - Extract page content as markdown

**Advanced:**
- **JidoBrowser.Actions.Evaluate** - Execute JavaScript

## Code Style Guidelines

- Use `@moduledoc` for module documentation following existing patterns
- TypeSpecs: Define `@type` for custom types, use strict typing throughout
- Actions use `use Jido.Action` with compile-time config (name, description, schema)
- Parameter validation via NimbleOptions schemas in action definitions
- Error handling: Return `{:ok, result}` or `{:error, reason}` tuples consistently
- Session is passed via context (tool_context pattern from jido_action)
- Use Zoi for struct schemas, Splode for errors

## Session Context Pattern

Browser session should be injected via agent hooks:

```elixir
# In agent's on_before_cmd/3:
def on_before_cmd(_agent, _cmd, context) do
  {:ok, session} = JidoBrowser.start_session()
  {:ok, Map.put(context, :tool_context, %{session: session})}
end

# Actions retrieve session from context:
defp get_session(context) do
  context[:session] ||
    context[:browser_session] ||
    get_in(context, [:tool_context, :session])
end
```

## Adding a New Adapter

1. Create module implementing `JidoBrowser.Adapter` behaviour
2. Implement all callbacks: `start_session/1`, `end_session/1`, `navigate/3`, etc.
3. Add configuration section to README
4. Add tests in `test/jido_browser/adapters/`

## Git Commit Guidelines

Use **Conventional Commits** format:

```
<type>[optional scope]: <description>
```

**Types:** `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`

**Examples:**
```
feat(actions): add scroll action
fix(vibium): handle connection timeout
docs: update adapter configuration
test(web): add LiveView navigation tests
```
