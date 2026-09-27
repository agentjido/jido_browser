defmodule Jido.Browser.Plugin.All do
  @moduledoc """
  Browser plugin with all registered browser actions.

  Use this module to restore the complete action set from Jido Browser 2.x.
  """

  alias Jido.Browser.Plugin

  use Jido.Browser.Plugin.Profile, profile: :all

  @doc false
  def mount(agent, config), do: Plugin.mount(agent, config)

  @doc false
  def handle_signal(signal, context), do: Plugin.handle_signal(signal, context)

  @doc false
  def transform_result(action, result, context),
    do: Plugin.transform_result(action, result, context)
end
