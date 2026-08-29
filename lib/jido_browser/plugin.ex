defmodule Jido.Browser.Plugin do
  @moduledoc """
  A Jido.Plugin providing browser automation capabilities for AI agents.

  This plugin owns browser session lifecycle and provides profiles for web
  navigation, interaction, content extraction, and diagnostics.

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

  ## Tool Profiles

  * `Jido.Browser.Plugin` - Normal navigation, interaction, waits, page reading,
    screenshots, and session close operations
  * `Jido.Browser.Plugin.Debug` - The core actions plus status, page identity,
    console, error, and JavaScript diagnostics
  * `Jido.Browser.Plugin.All` - Every action in `Jido.Browser.ActionRegistry`

  Use `Jido.Browser.Plugin.All` to restore the complete action set from Jido
  Browser 2.x. Each profile is a separate module so Jido can compile its exact
  action and signal contract from static plugin metadata.
  """

  alias Jido.Browser.Plugin.Profile

  use Profile, profile: :core

  @impl Jido.Plugin
  def mount(_agent, config) do
    :ok = Profile.reject_profile_option!(config)
    adapter = Map.get(config, :adapter, Jido.Browser.Adapters.AgentBrowser)

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
        current_url = Map.get(result, :url) || get_in(session, [:connection, :current_url])
        current_title = Map.get(result, :title) || get_in(session, [:connection, :title])

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
      [Map.get(result, :url), Map.get(result, :final_url)]
      |> Enum.reject(&nil_or_empty?/1)

    search_urls =
      result
      |> Map.get(:results, [])
      |> List.wrap()
      |> Enum.map(fn item ->
        if is_map(item), do: Map.get(item, :url)
      end)
      |> Enum.reject(&nil_or_empty?/1)

    direct_urls ++ search_urls
  end

  defp nil_or_empty?(nil), do: true
  defp nil_or_empty?(""), do: true
  defp nil_or_empty?(_value), do: false
end
