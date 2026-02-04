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
    {:jido_browser, "~> 0.8.0"}
  ]
end
```

### Automatic Binary Installation

After adding the dependency, install the browser backend:

```bash
mix jido_browser.install
```

This automatically detects your platform (macOS, Linux, Windows) and installs the appropriate binary.

### Recommended Setup

Add to your `mix.exs` aliases for automatic installation:

```elixir
defp aliases do
  [
    setup: ["deps.get", "jido_browser.install --if-missing"],
    test: ["jido_browser.install --if-missing", "test"]
  ]
end
```

### Platform Support

| Platform | Vibium | Web |
|----------|--------|-----|
| macOS (Apple Silicon) | ✓ | ✓ |
| macOS (Intel) | ✓ | ✓ |
| Linux (x86_64) | ✓ | ✓ |
| Linux (ARM64) | ✓ | ✓ |
| Windows (x86_64) | ✓ | ✗ |

### Browser Backends

**Vibium (Default)** - Uses npm for installation:

```bash
mix jido_browser.install vibium
```

**chrismccord/web** - Direct binary download:

```bash
mix jido_browser.install web
```

### Manual Installation (if needed)

**Vibium:**
```bash
npm install -g vibium @vibium/darwin-arm64  # or your platform
```

**Web:**
```bash
# Download from https://github.com/chrismccord/web
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

### Session Lifecycle
| Action | Description |
|--------|-------------|
| `StartSession` | Start a new browser session |
| `EndSession` | End the current session |
| `GetStatus` | Get session status (url, title, alive) |

### Navigation
| Action | Description |
|--------|-------------|
| `Navigate` | Navigate to a URL |
| `Back` | Go back in browser history |
| `Forward` | Go forward in browser history |
| `Reload` | Reload current page |
| `GetUrl` | Get current page URL |
| `GetTitle` | Get current page title |

### Interaction
| Action | Description |
|--------|-------------|
| `Click` | Click an element by CSS selector |
| `Type` | Type text into an input element |
| `Hover` | Hover over an element |
| `Focus` | Focus on an element |
| `Scroll` | Scroll page or element |
| `SelectOption` | Select option from dropdown |

### Waiting/Synchronization
| Action | Description |
|--------|-------------|
| `Wait` | Wait for specified milliseconds |
| `WaitForSelector` | Wait for element (visible/hidden/attached/detached) |
| `WaitForNavigation` | Wait for page navigation |

### Element Queries
| Action | Description |
|--------|-------------|
| `Query` | Query elements matching selector |
| `GetText` | Get text content of element |
| `GetAttribute` | Get attribute value from element |
| `IsVisible` | Check if element is visible |

### Content Extraction
| Action | Description |
|--------|-------------|
| `Snapshot` | Get comprehensive page snapshot (LLM-optimized) |
| `Screenshot` | Capture page screenshot |
| `ExtractContent` | Extract page content as markdown/HTML |

### Advanced
| Action | Description |
|--------|-------------|
| `Evaluate` | Execute arbitrary JavaScript |

## Using JidoBrowser.Plugin

The recommended way to use JidoBrowser with Jido agents is via the Plugin:

```elixir
defmodule MyBrowsingAgent do
  use Jido.Agent,
    name: "web_browser",
    description: "An agent that can browse the web",
    plugins: [{JidoBrowser.Plugin, [headless: true]}]
end
```

The Plugin provides:
- Session lifecycle management
- 26 browser automation actions
- Signal routing (`browser.*` patterns)
- Error diagnostics with page context

## License

Apache-2.0 - See [LICENSE](LICENSE) for details.
