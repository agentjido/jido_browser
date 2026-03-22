defmodule Jido.Browser.AgentBrowser.PoolRootSupervisor do
  @moduledoc false

  use Supervisor

  @doc false
  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, :ok, Keyword.put_new(opts, :name, __MODULE__))
  end

  @impl true
  def init(:ok) do
    children = [
      {Registry, keys: :unique, name: Jido.Browser.AgentBrowser.PoolRegistry},
      {DynamicSupervisor, strategy: :one_for_one, name: Jido.Browser.AgentBrowser.PoolSupervisor}
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end
end
