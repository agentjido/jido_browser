defmodule Jido.Browser.Deprecations do
  @moduledoc false

  use GenServer

  require Logger

  # Literal module atoms preserve exact selections without compile dependencies.
  @agent_browser :"Elixir.Jido.Browser.Adapters.AgentBrowser"
  @browsey_backend :"Elixir.Jido.Browser.WebFetch.Backends.Browsey"
  @browsey_http :"Elixir.Jido.Browser.Vendor.BrowseyHttp"
  @state_key {__MODULE__, :boot_warning_state}
  @web_adapter :"Elixir.Jido.Browser.Adapters.Web"

  @web_warning "#{inspect(@web_adapter)} (the Web adapter runtime) is deprecated and will be removed in " <>
                 "Jido Browser 3.0. Use #{inspect(@agent_browser)} instead."

  @browsey_warning "BrowseyHttp (the :browsey web-fetch runtime) is deprecated and will be removed in " <>
                     "Jido Browser 3.0. Use Jido.Browser.WebFetch.Backends.Req for HTTP retrieval, " <>
                     "or #{inspect(@agent_browser)} for rendered pages."

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc false
  @spec warn(term()) :: :ok
  def warn(selection) do
    case Process.whereis(__MODULE__) do
      pid when is_pid(pid) -> safe_warn(pid, selection)
      nil -> :ok
    end
  end

  @doc false
  @spec reset_boot_state() :: :ok
  def reset_boot_state do
    :persistent_term.put(@state_key, MapSet.new())
    :ok
  end

  @impl true
  def init(_opts) do
    warned =
      [configured_adapter(), configured_web_fetch_backend()]
      |> Enum.reduce(boot_warning_state(), &warn_once/2)

    {:ok, warned}
  end

  @impl true
  def handle_call({:warn, selection}, _from, warned) do
    {:reply, :ok, warn_once(selection, warned)}
  end

  defp safe_warn(pid, selection) do
    GenServer.call(pid, {:warn, selection})
  catch
    :exit, _reason -> :ok
  end

  defp warn_once(selection, warned) do
    case deprecation(selection) do
      {key, message} ->
        if MapSet.member?(warned, key) do
          warned
        else
          warned = MapSet.put(warned, key)
          :persistent_term.put(@state_key, warned)
          Logger.warning(message)
          warned
        end

      nil ->
        warned
    end
  end

  defp deprecation(@web_adapter), do: {:web, @web_warning}
  defp deprecation(:web), do: {:web, @web_warning}
  defp deprecation(@browsey_backend), do: {:browsey, @browsey_warning}
  defp deprecation(@browsey_http), do: {:browsey, @browsey_warning}
  defp deprecation(:browsey), do: {:browsey, @browsey_warning}
  defp deprecation(_selection), do: nil

  defp boot_warning_state do
    :persistent_term.get(@state_key, MapSet.new())
  end

  defp configured_adapter do
    Application.get_env(:jido_browser, :adapter, @agent_browser)
  end

  defp configured_web_fetch_backend do
    case Application.get_env(:jido_browser, :web_fetch, []) do
      config when is_list(config) ->
        if Keyword.keyword?(config), do: Keyword.get(config, :backend)

      config when is_map(config) ->
        Map.get(config, :backend)

      _config ->
        nil
    end
  end
end
