defmodule Jido.Browser.Plugin.All do
  @moduledoc """
  Browser plugin with all registered browser actions.

  Use this module to restore the complete action set from Jido Browser 2.x.
  """

  use Jido.Browser.Plugin.Profile, profile: :all

  @impl Jido.Plugin
  def mount(agent, config), do: Jido.Browser.Plugin.mount(agent, config)

  @impl Jido.Plugin
  def handle_signal(signal, context), do: Jido.Browser.Plugin.handle_signal(signal, context)

  @impl Jido.Plugin
  def transform_result(action, result, context),
    do: Jido.Browser.Plugin.transform_result(action, result, context)
end
