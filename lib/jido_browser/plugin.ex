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
  * `:pool` - Named warm session pool for a pool-capable adapter (optional)
  * `:checkout_timeout` - Warm pool checkout timeout in milliseconds (default: `5_000`)
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

  alias Jido.Browser.ActionRegistry
  alias Jido.Browser.Deprecations

  @action_modules ActionRegistry.actions()
  @signal_routes ActionRegistry.signal_routes()
  @signal_patterns ActionRegistry.signal_patterns()

  use Jido.Plugin,
    name: "browser",
    state_key: :browser,
    actions: @action_modules,
    signal_patterns: @signal_patterns,
    description: "Browser automation for web navigation, interaction, and content extraction",
    category: "browser",
    tags: ["browser", "web", "automation", "scraping"],
    vsn: "2.0.0"

  @impl Jido.Plugin
  def mount(_agent, config) do
    adapter = Map.get(config, :adapter, Jido.Browser.Adapters.AgentBrowser)
    :ok = Deprecations.warn(adapter)

    initial_state = %{
      session: nil,
      headless: Map.get(config, :headless, true),
      timeout: Map.get(config, :timeout, 30_000),
      adapter: adapter,
      pool: Map.get(config, :pool),
      checkout_timeout: Map.get(config, :checkout_timeout, 5_000),
      viewport: Map.get(config, :viewport, %{width: 1280, height: 720}),
      base_url: Map.get(config, :base_url),
      last_url: nil,
      last_title: nil,
      seen_urls: [],
      web_fetch_uses: 0,
      fetch_rich_uses: 0
    }

    {:ok, initial_state}
  end

  def schema do
    Zoi.object(%{
      session: Zoi.any(description: "Active browser session") |> Zoi.optional(),
      headless: Zoi.boolean(description: "Run browser in headless mode") |> Zoi.default(true),
      timeout: Zoi.integer(description: "Default timeout in milliseconds") |> Zoi.default(30_000),
      adapter: Zoi.atom(description: "Browser adapter module") |> Zoi.optional(),
      pool: Zoi.any(description: "Named warm session pool") |> Zoi.optional(),
      checkout_timeout: Zoi.integer(description: "Warm pool checkout timeout in milliseconds") |> Zoi.default(5_000),
      viewport: Zoi.any(description: "Browser viewport dimensions") |> Zoi.optional(),
      base_url: Zoi.string(description: "Base URL for relative navigation") |> Zoi.optional(),
      last_url: Zoi.string(description: "Last navigated URL") |> Zoi.optional(),
      last_title: Zoi.string(description: "Last page title") |> Zoi.optional(),
      seen_urls: Zoi.array(Zoi.string(description: "Known URLs discovered during tool use")) |> Zoi.default([]),
      web_fetch_uses: Zoi.integer(description: "Successful web fetch calls in current skill state") |> Zoi.default(0),
      fetch_rich_uses: Zoi.integer(description: "Successful rich fetch calls in current skill state") |> Zoi.default(0)
    })
  end

  @impl Jido.Plugin
  def signal_routes(_config), do: @signal_routes

  @impl Jido.Plugin
  def handle_signal(_signal, _context) do
    {:ok, :continue}
  end

  @impl Jido.Plugin
  def transform_result(action, {:ok, result}, context) when is_map(result) do
    state_updates =
      %{}
      |> maybe_put_session_state(result)
      |> maybe_put_seen_urls(result, context)
      |> maybe_increment_web_fetch_uses(action, context)

    if map_size(state_updates) == 0 do
      {:ok, result}
    else
      {:ok, result, state_updates}
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
           adapter: get_in(context, [:skill_state, :adapter]),
           pool: get_in(context, [:skill_state, :pool]),
           hint: "Use browser.screenshot, browser.console, or browser.errors for live-session debugging"
         }}
    end
  end

  defp maybe_put_session_state(acc, result) do
    case Map.get(result, :session) do
      %Jido.Browser.Session{} = session ->
        current_url = Map.get(result, :url) || Map.get(result, "url") || get_in(session, [:connection, :current_url])
        current_title = Map.get(result, :title) || Map.get(result, "title") || get_in(session, [:connection, :title])

        Map.merge(acc, %{
          session: session,
          last_url: current_url,
          last_title: current_title
        })

      _ ->
        acc
    end
  end

  defp maybe_put_seen_urls(acc, result, context) do
    current_seen_urls = get_in(context, [:skill_state, :seen_urls]) || []

    seen_urls =
      current_seen_urls
      |> Kernel.++(extract_urls(result))
      |> Enum.reject(&nil_or_empty?/1)
      |> Enum.uniq()

    if seen_urls == [] or seen_urls == current_seen_urls do
      acc
    else
      Map.put(acc, :seen_urls, seen_urls)
    end
  end

  defp maybe_increment_web_fetch_uses(acc, Jido.Browser.Actions.WebFetch, context) do
    current_uses = get_in(context, [:skill_state, :web_fetch_uses]) || 0
    Map.put(acc, :web_fetch_uses, current_uses + 1)
  end

  defp maybe_increment_web_fetch_uses(acc, Jido.Browser.Actions.FetchRich, context) do
    current_uses = get_in(context, [:skill_state, :fetch_rich_uses]) || 0
    Map.put(acc, :fetch_rich_uses, current_uses + 1)
  end

  defp maybe_increment_web_fetch_uses(acc, _action, _context), do: acc

  defp extract_urls(result) do
    direct_urls =
      [Map.get(result, :url), Map.get(result, "url"), Map.get(result, :final_url), Map.get(result, "final_url")]
      |> Enum.reject(&nil_or_empty?/1)

    search_urls =
      result
      |> Map.get(:results, Map.get(result, "results", []))
      |> List.wrap()
      |> Enum.map(fn item ->
        if is_map(item), do: Map.get(item, :url) || Map.get(item, "url")
      end)
      |> Enum.reject(&nil_or_empty?/1)

    direct_urls ++ search_urls
  end

  defp nil_or_empty?(nil), do: true
  defp nil_or_empty?(""), do: true
  defp nil_or_empty?(_value), do: false
end
