# Ensure actions are compiled before the plugin
require JidoBrowser.Actions.Back
require JidoBrowser.Actions.Click
require JidoBrowser.Actions.EndSession
require JidoBrowser.Actions.Evaluate
require JidoBrowser.Actions.ExtractContent
require JidoBrowser.Actions.Focus
require JidoBrowser.Actions.Forward
require JidoBrowser.Actions.GetAttribute
require JidoBrowser.Actions.GetStatus
require JidoBrowser.Actions.GetText
require JidoBrowser.Actions.GetTitle
require JidoBrowser.Actions.GetUrl
require JidoBrowser.Actions.Hover
require JidoBrowser.Actions.IsVisible
require JidoBrowser.Actions.Navigate
require JidoBrowser.Actions.Query
require JidoBrowser.Actions.Reload
require JidoBrowser.Actions.Screenshot
require JidoBrowser.Actions.Scroll
require JidoBrowser.Actions.SelectOption
require JidoBrowser.Actions.Snapshot
require JidoBrowser.Actions.StartSession
require JidoBrowser.Actions.Type
require JidoBrowser.Actions.Wait
require JidoBrowser.Actions.WaitForNavigation
require JidoBrowser.Actions.WaitForSelector

defmodule JidoBrowser.Plugin do
  @moduledoc """
  A Jido.Plugin providing browser automation capabilities for AI agents.

  This plugin owns browser session lifecycle and provides a complete set of
  actions for web navigation, interaction, and content extraction.

  ## Usage

      defmodule MyAgent do
        use Jido.Agent,
          plugins: [{JidoBrowser.Plugin, [headless: true]}]
      end

  ## Configuration Options

  * `:headless` - Run browser in headless mode (default: `true`)
  * `:timeout` - Default timeout in milliseconds (default: `30_000`)
  * `:adapter` - Browser adapter module (optional)
  * `:viewport` - Browser viewport dimensions (default: `%{width: 1280, height: 720}`)
  * `:base_url` - Base URL for relative navigation (optional)

  ## Actions

  * `Navigate` - Navigate to a URL
  * `Click` - Click an element by selector
  * `Type` - Type text into an input element
  * `Screenshot` - Take a screenshot of the current page
  * `ExtractContent` - Extract page content as markdown or HTML
  * `Evaluate` - Execute JavaScript in the browser
  """

  use Jido.Plugin,
    name: "browser",
    state_key: :browser,
    actions: [
      # Session lifecycle
      JidoBrowser.Actions.StartSession,
      JidoBrowser.Actions.EndSession,
      JidoBrowser.Actions.GetStatus,
      # Navigation
      JidoBrowser.Actions.Navigate,
      JidoBrowser.Actions.Back,
      JidoBrowser.Actions.Forward,
      JidoBrowser.Actions.Reload,
      JidoBrowser.Actions.GetUrl,
      JidoBrowser.Actions.GetTitle,
      # Interaction
      JidoBrowser.Actions.Click,
      JidoBrowser.Actions.Type,
      JidoBrowser.Actions.Hover,
      JidoBrowser.Actions.Focus,
      JidoBrowser.Actions.Scroll,
      JidoBrowser.Actions.SelectOption,
      # Waiting/synchronization
      JidoBrowser.Actions.Wait,
      JidoBrowser.Actions.WaitForSelector,
      JidoBrowser.Actions.WaitForNavigation,
      # Element queries
      JidoBrowser.Actions.Query,
      JidoBrowser.Actions.GetText,
      JidoBrowser.Actions.GetAttribute,
      JidoBrowser.Actions.IsVisible,
      # Content extraction
      JidoBrowser.Actions.Snapshot,
      JidoBrowser.Actions.Screenshot,
      JidoBrowser.Actions.ExtractContent,
      # Advanced
      JidoBrowser.Actions.Evaluate
    ],
    description: "Browser automation for web navigation, interaction, and content extraction",
    category: "browser",
    tags: ["browser", "web", "automation", "scraping"],
    vsn: "1.0.0"

  @impl Jido.Plugin
  def mount(_agent, config) do
    initial_state = %{
      session: nil,
      headless: Map.get(config, :headless, true),
      timeout: Map.get(config, :timeout, 30_000),
      adapter: Map.get(config, :adapter),
      viewport: Map.get(config, :viewport, %{width: 1280, height: 720}),
      base_url: Map.get(config, :base_url),
      last_url: nil,
      last_title: nil
    }

    {:ok, initial_state}
  end

  def schema do
    Zoi.object(%{
      session: Zoi.any(description: "Active browser session") |> Zoi.optional(),
      headless: Zoi.boolean(description: "Run browser in headless mode") |> Zoi.default(true),
      timeout: Zoi.integer(description: "Default timeout in milliseconds") |> Zoi.default(30_000),
      adapter: Zoi.atom(description: "Browser adapter module") |> Zoi.optional(),
      viewport: Zoi.any(description: "Browser viewport dimensions") |> Zoi.optional(),
      base_url: Zoi.string(description: "Base URL for relative navigation") |> Zoi.optional(),
      last_url: Zoi.string(description: "Last navigated URL") |> Zoi.optional(),
      last_title: Zoi.string(description: "Last page title") |> Zoi.optional()
    })
  end

  @impl Jido.Plugin
  def signal_routes(_config) do
    [
      # Session lifecycle
      {"browser.start_session", JidoBrowser.Actions.StartSession},
      {"browser.end_session", JidoBrowser.Actions.EndSession},
      {"browser.get_status", JidoBrowser.Actions.GetStatus},
      # Navigation
      {"browser.navigate", JidoBrowser.Actions.Navigate},
      {"browser.back", JidoBrowser.Actions.Back},
      {"browser.forward", JidoBrowser.Actions.Forward},
      {"browser.reload", JidoBrowser.Actions.Reload},
      {"browser.get_url", JidoBrowser.Actions.GetUrl},
      {"browser.get_title", JidoBrowser.Actions.GetTitle},
      # Interaction
      {"browser.click", JidoBrowser.Actions.Click},
      {"browser.type", JidoBrowser.Actions.Type},
      {"browser.hover", JidoBrowser.Actions.Hover},
      {"browser.focus", JidoBrowser.Actions.Focus},
      {"browser.scroll", JidoBrowser.Actions.Scroll},
      {"browser.select_option", JidoBrowser.Actions.SelectOption},
      # Waiting/synchronization
      {"browser.wait", JidoBrowser.Actions.Wait},
      {"browser.wait_for_selector", JidoBrowser.Actions.WaitForSelector},
      {"browser.wait_for_navigation", JidoBrowser.Actions.WaitForNavigation},
      # Element queries
      {"browser.query", JidoBrowser.Actions.Query},
      {"browser.get_text", JidoBrowser.Actions.GetText},
      {"browser.get_attribute", JidoBrowser.Actions.GetAttribute},
      {"browser.is_visible", JidoBrowser.Actions.IsVisible},
      # Content extraction
      {"browser.snapshot", JidoBrowser.Actions.Snapshot},
      {"browser.screenshot", JidoBrowser.Actions.Screenshot},
      {"browser.extract", JidoBrowser.Actions.ExtractContent},
      # Advanced
      {"browser.evaluate", JidoBrowser.Actions.Evaluate}
    ]
  end

  @impl Jido.Plugin
  def handle_signal(_signal, _context) do
    {:ok, :continue}
  end

  @impl Jido.Plugin
  def transform_result(_action, {:ok, result}, _context) when is_map(result) do
    case Map.get(result, :session) do
      %JidoBrowser.Session{} = session ->
        current_url = get_in(session, [:connection, :current_url])

        state_updates = %{
          session: session,
          last_url: current_url
        }

        {:ok, result, state_updates}

      _ ->
        {:ok, result}
    end
  end

  def transform_result(_action, {:error, error} = _result, context) do
    case get_diagnostics(context) do
      {:ok, diagnostics} ->
        {:error, %{error: error, diagnostics: diagnostics}}

      _ ->
        {:error, error}
    end
  end

  def transform_result(_action, result, _context), do: result

  defp get_diagnostics(context) do
    case get_in(context, [:skill_state, :session]) do
      nil ->
        {:error, :no_session}

      _session ->
        {:ok,
         %{
           url: get_in(context, [:skill_state, :last_url]),
           title: get_in(context, [:skill_state, :last_title]),
           hint: "Use browser.screenshot for visual debugging"
         }}
    end
  end

  def signal_patterns do
    [
      # Session lifecycle
      "browser.start_session",
      "browser.end_session",
      "browser.get_status",
      # Navigation
      "browser.navigate",
      "browser.back",
      "browser.forward",
      "browser.reload",
      "browser.get_url",
      "browser.get_title",
      # Interaction
      "browser.click",
      "browser.type",
      "browser.hover",
      "browser.focus",
      "browser.scroll",
      "browser.select_option",
      # Waiting/synchronization
      "browser.wait",
      "browser.wait_for_selector",
      "browser.wait_for_navigation",
      # Element queries
      "browser.query",
      "browser.get_text",
      "browser.get_attribute",
      "browser.is_visible",
      # Content extraction
      "browser.snapshot",
      "browser.screenshot",
      "browser.extract",
      # Advanced
      "browser.evaluate"
    ]
  end
end
