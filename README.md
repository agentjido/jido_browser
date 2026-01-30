# Jido Browser

[![Hex.pm](https://img.shields.io/hexpm/v/jido_browser.svg)](https://hex.pm/packages/jido_browser)
[![Docs](https://img.shields.io/badge/docs-hexdocs-blue.svg)](https://hexdocs.pm/jido_browser)
[![CI](https://github.com/agentjido/jido_browser/actions/workflows/ci.yml/badge.svg)](https://github.com/agentjido/jido_browser/actions/workflows/ci.yml)

Browser automation actions for Jido AI agents.

## Overview

JidoBrowser provides a set of Jido Actions for web browsing, enabling AI agents to navigate, interact with, and extract content from web pages. It uses an adapter pattern to support multiple browser automation backends.

## Installation

Add `jido_browser` to your dependencies:

```elixir
def deps do
  [
    {:jido_browser, "~> 0.1.0"}
  ]
end
```

### Browser Backend

JidoBrowser supports multiple browser backends via adapters:

**Vibium (Recommended)**

```bash
npm install -g vibium
```

**chrismccord/web**

```bash
# Download from https://github.com/chrismccord/web
# Or build from source
git clone https://github.com/chrismccord/web
cd web && make && sudo cp web /usr/local/bin/
```

## Quick Start

```elixir
# Start a browser session
{:ok, session} = JidoBrowser.start_session()

# Navigate to a page
{:ok, _} = JidoBrowser.navigate(session, "https://example.com")

# Click an element
{:ok, _} = JidoBrowser.click(session, "button#submit")

# Type into an input
{:ok, _} = JidoBrowser.type(session, "input#search", "hello world")

# Take a screenshot
{:ok, %{bytes: png_data}} = JidoBrowser.screenshot(session)

# Extract page content as markdown (great for LLMs)
{:ok, %{content: markdown}} = JidoBrowser.extract_content(session)

# End session
:ok = JidoBrowser.end_session(session)
```

## Using with Jido Agents

JidoBrowser actions integrate seamlessly with Jido agents:

```elixir
defmodule MyBrowsingAgent do
  use Jido.Agent,
    name: "web_browser",
    description: "An agent that can browse the web",
    tools: [
      JidoBrowser.Actions.Navigate,
      JidoBrowser.Actions.Click,
      JidoBrowser.Actions.Type,
      JidoBrowser.Actions.Screenshot,
      JidoBrowser.Actions.ExtractContent
    ]

  # Inject browser session via on_before_cmd hook
  def on_before_cmd(_agent, _cmd, context) do
    {:ok, session} = JidoBrowser.start_session()
    {:ok, Map.put(context, :tool_context, %{session: session})}
  end
end
```

## Configuration

```elixir
config :jido_browser,
  adapter: JidoBrowser.Adapters.Vibium,
  timeout: 30_000

# Vibium-specific options
config :jido_browser, :vibium,
  binary_path: "/usr/local/bin/vibium",
  port: 9515

# Web adapter options
config :jido_browser, :web,
  binary_path: "/usr/local/bin/web",
  profile: "default"
```

## Adapters

### Vibium (Default)

- WebDriver BiDi protocol (standards-based)
- Automatic Chrome download
- ~10MB Go binary
- Built-in MCP server

### chrismccord/web

- Firefox-based via Selenium
- Built-in HTML to Markdown conversion
- Phoenix LiveView-aware
- Session persistence with profiles

## Available Actions

| Action | Description |
|--------|-------------|
| `Navigate` | Navigate to a URL |
| `Click` | Click an element by CSS selector |
| `Type` | Type text into an input element |
| `Screenshot` | Capture page screenshot |
| `ExtractContent` | Extract page content as markdown/HTML |
| `Evaluate` | Execute JavaScript |

## License

Apache-2.0 - See [LICENSE](LICENSE) for details.
