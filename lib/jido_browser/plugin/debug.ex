defmodule Jido.Browser.Plugin.Debug do
  @moduledoc """
  Browser plugin with the core actions and diagnostic actions.

  Use this module when an agent also needs status, page identity, console,
  browser error, and JavaScript evaluation actions.
  """

  alias Jido.Browser.Plugin

  use Jido.Browser.Plugin.Profile, profile: :debug

  @doc false
  def mount(agent, config), do: Plugin.mount(agent, config)

  @doc false
  def handle_signal(signal, context), do: Plugin.handle_signal(signal, context)

  @doc false
  def transform_result(action, result, context),
    do: Plugin.transform_result(action, result, context)
end
