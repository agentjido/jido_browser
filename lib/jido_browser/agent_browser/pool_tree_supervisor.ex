defmodule Jido.Browser.AgentBrowser.PoolTreeSupervisor do
  @moduledoc false

  use Supervisor

  alias Jido.Browser.AgentBrowser.PoolManager
  alias Jido.Browser.AgentBrowser.PoolNames
  alias Jido.Browser.Application, as: BrowserApplication

  @doc false
  @spec start_pool(keyword()) :: DynamicSupervisor.on_start_child()
  def start_pool(opts) do
    with :ok <- BrowserApplication.ensure_started() do
      child_spec = {__MODULE__, opts}
      DynamicSupervisor.start_child(Jido.Browser.AgentBrowser.PoolSupervisor, child_spec)
    end
  end

  @doc false
  @spec stop_pool(term()) :: :ok | {:error, term()}
  def stop_pool(pool) do
    with {:ok, pid} <- PoolNames.resolve_tree(pool) do
      stop_tree(pid)
    end
  catch
    :exit, reason ->
      {:error, reason}
  end

  @doc false
  @spec await_ready(term(), timeout()) :: :ok
  def await_ready(pool, timeout) do
    with {:ok, pid} <- PoolNames.resolve_manager(pool) do
      PoolManager.await_ready(pid, timeout)
    end
  end

  @doc false
  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    Supervisor.start_link(__MODULE__, opts, name: PoolNames.tree(name))
  end

  @doc false
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id: {__MODULE__, Keyword.fetch!(opts, :name)},
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor
    }
  end

  @impl true
  def init(opts) do
    name = Keyword.fetch!(opts, :name)

    children = [
      {DynamicSupervisor, strategy: :one_for_one, name: PoolNames.session_supervisor(name)},
      {DynamicSupervisor, strategy: :one_for_one, name: PoolNames.lease_supervisor(name)},
      {Task.Supervisor, name: PoolNames.cleanup_supervisor(name)},
      {PoolManager,
       opts
       |> Keyword.put(:process_name, PoolNames.manager(name))
       |> Keyword.put(:pool_tree, self())
       |> Keyword.put(:session_supervisor, PoolNames.session_supervisor(name))
       |> Keyword.put(:lease_supervisor, PoolNames.lease_supervisor(name))
       |> Keyword.put(:cleanup_supervisor, PoolNames.cleanup_supervisor(name))}
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end

  defp stop_tree(pid) do
    case DynamicSupervisor.terminate_child(Jido.Browser.AgentBrowser.PoolSupervisor, pid) do
      :ok -> :ok
      {:error, :not_found} -> Supervisor.stop(pid, :normal, 30_000)
    end
  end
end
