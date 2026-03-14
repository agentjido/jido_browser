defmodule Jido.Browser.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Registry, keys: :unique, name: Jido.Browser.AgentBrowser.Registry},
      {DynamicSupervisor, strategy: :one_for_one, name: Jido.Browser.AgentBrowser.SessionSupervisor}
    ]

    Supervisor.start_link(children,
      strategy: :one_for_one,
      name: Jido.Browser.Supervisor
    )
  end
end
