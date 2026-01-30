# Jido Browser - LLM Usage Rules

## Overview

JidoBrowser provides browser automation actions for AI agents. Use these rules when generating code that uses JidoBrowser.

## Key Patterns

### Session Management

Always start a session before browser operations:

```elixir
{:ok, session} = JidoBrowser.start_session()
# ... operations ...
:ok = JidoBrowser.end_session(session)
```

### Context Injection for Agents

When using with Jido agents, inject the session via `tool_context`:

```elixir
def on_before_cmd(_agent, _cmd, context) do
  {:ok, session} = JidoBrowser.start_session()
  {:ok, Map.put(context, :tool_context, %{session: session})}
end
```

### Available Actions

- `JidoBrowser.Actions.Navigate` - Navigate to URL
- `JidoBrowser.Actions.Click` - Click element
- `JidoBrowser.Actions.Type` - Type into input
- `JidoBrowser.Actions.Screenshot` - Capture screenshot
- `JidoBrowser.Actions.ExtractContent` - Get page content as markdown
- `JidoBrowser.Actions.Evaluate` - Run JavaScript

### Error Handling

All operations return `{:ok, result}` or `{:error, JidoBrowser.Error.*}`:

```elixir
case JidoBrowser.navigate(session, url) do
  {:ok, result} -> handle_success(result)
  {:error, %JidoBrowser.Error.NavigationError{}} -> handle_nav_error()
  {:error, %JidoBrowser.Error.TimeoutError{}} -> handle_timeout()
end
```

## Don'ts

- Don't create sessions without ending them
- Don't hardcode selectors that may change
- Don't assume elements exist without checking
- Don't run browser operations without a session in context
