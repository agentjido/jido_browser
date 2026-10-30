defmodule Jido.Browser.Plugin.Agent do
  @moduledoc false

  @behaviour Jido.Plugin

  alias Jido.Browser.Plugin
  alias Jido.Browser.Plugin.Profile

  @impl true
  def state_spec(opts) do
    config = Map.new(opts)
    :ok = Profile.reject_profile_option!(config)
    {:ok, state} = Plugin.mount(%{}, config)
    {:browser, Profile.state_schema() |> Zoi.default(state)}
  end

  @impl true
  def prepare(%Jido.Agent.Plugin.Preparation{plugin_state: state}, _opts), do: {:ok, state}

  @impl true
  def reduce(%Jido.Agent.Plugin.Reduction{plugin_state: state}, _opts), do: {:ok, state}
end
