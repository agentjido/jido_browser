# Ensure actions are compiled before the plugin
require Jido.Browser.Actions.Back
require Jido.Browser.Actions.Click
require Jido.Browser.Actions.CloseTab
require Jido.Browser.Actions.Console
require Jido.Browser.Actions.EndSession
require Jido.Browser.Actions.Evaluate
require Jido.Browser.Actions.Errors
require Jido.Browser.Actions.ExtractContent
require Jido.Browser.Actions.Focus
require Jido.Browser.Actions.Forward
require Jido.Browser.Actions.GetAttribute
require Jido.Browser.Actions.GetStatus
require Jido.Browser.Actions.GetText
require Jido.Browser.Actions.GetTitle
require Jido.Browser.Actions.GetUrl
require Jido.Browser.Actions.Hover
require Jido.Browser.Actions.IsVisible
require Jido.Browser.Actions.ListTabs
require Jido.Browser.Actions.LoadState
require Jido.Browser.Actions.Navigate
require Jido.Browser.Actions.NewTab
require Jido.Browser.Actions.Query
require Jido.Browser.Actions.Reload
require Jido.Browser.Actions.SaveState
require Jido.Browser.Actions.Screenshot
require Jido.Browser.Actions.Scroll
require Jido.Browser.Actions.SelectOption
require Jido.Browser.Actions.Snapshot
require Jido.Browser.Actions.StartSession
require Jido.Browser.Actions.SwitchTab
require Jido.Browser.Actions.Type
require Jido.Browser.Actions.Wait
require Jido.Browser.Actions.WaitForNavigation
require Jido.Browser.Actions.WaitForSelector
require Jido.Browser.Actions.ReadPage
require Jido.Browser.Actions.SnapshotUrl
require Jido.Browser.Actions.SearchWeb

defmodule Jido.Browser.Plugin do
  @moduledoc """
  A Jido.Plugin providing browser automation capabilities for AI agents.

  This plugin owns browser session lifecycle and provides a complete set of
  actions for web navigation, interaction, and content extraction.

  ## Usage

      defmodule MyAgent do
        use Jido.Agent,
          plugins: [{Jido.Browser.Plugin, [headless: true]}]
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
      Jido.Browser.Actions.StartSession,
      Jido.Browser.Actions.EndSession,
      Jido.Browser.Actions.GetStatus,
      Jido.Browser.Actions.SaveState,
      Jido.Browser.Actions.LoadState,
      # Navigation
      Jido.Browser.Actions.Navigate,
      Jido.Browser.Actions.Back,
      Jido.Browser.Actions.Forward,
      Jido.Browser.Actions.Reload,
      Jido.Browser.Actions.GetUrl,
      Jido.Browser.Actions.GetTitle,
      # Interaction
      Jido.Browser.Actions.Click,
      Jido.Browser.Actions.Type,
      Jido.Browser.Actions.Hover,
      Jido.Browser.Actions.Focus,
      Jido.Browser.Actions.Scroll,
      Jido.Browser.Actions.SelectOption,
      # Waiting/synchronization
      Jido.Browser.Actions.Wait,
      Jido.Browser.Actions.WaitForSelector,
      Jido.Browser.Actions.WaitForNavigation,
      # Element queries
      Jido.Browser.Actions.Query,
      Jido.Browser.Actions.GetText,
      Jido.Browser.Actions.GetAttribute,
      Jido.Browser.Actions.IsVisible,
      # Tabs
      Jido.Browser.Actions.ListTabs,
      Jido.Browser.Actions.NewTab,
      Jido.Browser.Actions.SwitchTab,
      Jido.Browser.Actions.CloseTab,
      # Content extraction
      Jido.Browser.Actions.Snapshot,
      Jido.Browser.Actions.Screenshot,
      Jido.Browser.Actions.ExtractContent,
      # Diagnostics
      Jido.Browser.Actions.Console,
      Jido.Browser.Actions.Errors,
      # Advanced
      Jido.Browser.Actions.Evaluate,
      # Self-contained composite actions (manage own session)
      Jido.Browser.Actions.ReadPage,
      Jido.Browser.Actions.SnapshotUrl,
      Jido.Browser.Actions.SearchWeb
    ],
    description: "Browser automation for web navigation, interaction, and content extraction",
    category: "browser",
    tags: ["browser", "web", "automation", "scraping"],
    vsn: "2.0.0"

  @impl Jido.Plugin
  def mount(_agent, config) do
    initial_state = %{
      session: nil,
      headless: Map.get(config, :headless, true),
      timeout: Map.get(config, :timeout, 30_000),
      adapter: Map.get(config, :adapter, Jido.Browser.Adapters.AgentBrowser),
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
      {"browser.start_session", Jido.Browser.Actions.StartSession},
      {"browser.end_session", Jido.Browser.Actions.EndSession},
      {"browser.get_status", Jido.Browser.Actions.GetStatus},
      {"browser.save_state", Jido.Browser.Actions.SaveState},
      {"browser.load_state", Jido.Browser.Actions.LoadState},
      # Navigation
      {"browser.navigate", Jido.Browser.Actions.Navigate},
      {"browser.back", Jido.Browser.Actions.Back},
      {"browser.forward", Jido.Browser.Actions.Forward},
      {"browser.reload", Jido.Browser.Actions.Reload},
      {"browser.get_url", Jido.Browser.Actions.GetUrl},
      {"browser.get_title", Jido.Browser.Actions.GetTitle},
      # Interaction
      {"browser.click", Jido.Browser.Actions.Click},
      {"browser.type", Jido.Browser.Actions.Type},
      {"browser.hover", Jido.Browser.Actions.Hover},
      {"browser.focus", Jido.Browser.Actions.Focus},
      {"browser.scroll", Jido.Browser.Actions.Scroll},
      {"browser.select_option", Jido.Browser.Actions.SelectOption},
      # Waiting/synchronization
      {"browser.wait", Jido.Browser.Actions.Wait},
      {"browser.wait_for_selector", Jido.Browser.Actions.WaitForSelector},
      {"browser.wait_for_navigation", Jido.Browser.Actions.WaitForNavigation},
      # Element queries
      {"browser.query", Jido.Browser.Actions.Query},
      {"browser.get_text", Jido.Browser.Actions.GetText},
      {"browser.get_attribute", Jido.Browser.Actions.GetAttribute},
      {"browser.is_visible", Jido.Browser.Actions.IsVisible},
      # Tabs
      {"browser.tab_list", Jido.Browser.Actions.ListTabs},
      {"browser.tab_new", Jido.Browser.Actions.NewTab},
      {"browser.tab_switch", Jido.Browser.Actions.SwitchTab},
      {"browser.tab_close", Jido.Browser.Actions.CloseTab},
      # Content extraction
      {"browser.snapshot", Jido.Browser.Actions.Snapshot},
      {"browser.screenshot", Jido.Browser.Actions.Screenshot},
      {"browser.extract", Jido.Browser.Actions.ExtractContent},
      # Diagnostics
      {"browser.console", Jido.Browser.Actions.Console},
      {"browser.errors", Jido.Browser.Actions.Errors},
      # Advanced
      {"browser.evaluate", Jido.Browser.Actions.Evaluate},
      # Self-contained composite actions
      {"browser.read_page", Jido.Browser.Actions.ReadPage},
      {"browser.snapshot_url", Jido.Browser.Actions.SnapshotUrl},
      {"browser.search_web", Jido.Browser.Actions.SearchWeb}
    ]
  end

  @impl Jido.Plugin
  def handle_signal(_signal, _context) do
    {:ok, :continue}
  end

  @impl Jido.Plugin
  def transform_result(_action, {:ok, result}, _context) when is_map(result) do
    case Map.get(result, :session) do
      %Jido.Browser.Session{} = session ->
        current_url = Map.get(result, :url) || Map.get(result, "url") || get_in(session, [:connection, :current_url])
        current_title = Map.get(result, :title) || Map.get(result, "title") || get_in(session, [:connection, :title])

        state_updates = %{
          session: session,
          last_url: current_url,
          last_title: current_title
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
      "browser.save_state",
      "browser.load_state",
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
      # Tabs
      "browser.tab_list",
      "browser.tab_new",
      "browser.tab_switch",
      "browser.tab_close",
      # Content extraction
      "browser.snapshot",
      "browser.screenshot",
      "browser.extract",
      # Diagnostics
      "browser.console",
      "browser.errors",
      # Advanced
      "browser.evaluate",
      # Self-contained composite actions
      "browser.read_page",
      "browser.snapshot_url",
      "browser.search_web"
    ]
  end
end
