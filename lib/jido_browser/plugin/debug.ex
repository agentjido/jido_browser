defmodule Jido.Browser.Plugin.Debug do
  @moduledoc """
  Browser plugin with the core actions and diagnostic actions.

  Use this module when an agent also needs status, page identity, console,
  browser error, and JavaScript evaluation actions.
  """

  use Jido.Browser.Plugin.Profile, profile: :debug

  @impl Jido.Plugin
  def mount(agent, config), do: Jido.Browser.Plugin.mount(agent, config)

  @impl Jido.Plugin
  def handle_signal(signal, context), do: Jido.Browser.Plugin.handle_signal(signal, context)

  @impl Jido.Plugin
  def transform_result(action, result, context),
    do: Jido.Browser.Plugin.transform_result(action, result, context)
end
