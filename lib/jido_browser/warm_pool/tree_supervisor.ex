defmodule Jido.Browser.WarmPool.TreeSupervisor do
  @moduledoc false

  use Supervisor

  alias Jido.Browser.Application, as: BrowserApplication
  alias Jido.Browser.WarmPool.Manager
  alias Jido.Browser.WarmPool.Names

  @doc false
  @spec start_pool(keyword()) :: DynamicSupervisor.on_start_child()
  def start_pool(opts) do
    with :ok <- BrowserApplication.ensure_started() do
      child_spec = {__MODULE__, opts}
      DynamicSupervisor.start_child(Jido.Browser.WarmPool.Supervisor, child_spec)
    end
  end

  @doc false
  @spec stop_pool(term()) :: :ok | {:error, term()}
  def stop_pool(pool) do
    with {:ok, pid} <- Names.resolve_tree(pool) do
      _ = Manager.prepare_stop(pool)
      stop_tree(pid)
    end
  catch
    :exit, reason ->
      {:error, reason}
  end

  @doc false
  @spec await_ready(term(), timeout()) :: :ok
  def await_ready(pool, timeout) do
    with {:ok, pid} <- Names.resolve_manager(pool) do
      Manager.await_ready(pid, timeout)
    end
  end

  @doc false
  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    Supervisor.start_link(__MODULE__, opts, name: Names.tree(name))
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
      {DynamicSupervisor, strategy: :one_for_one, name: Names.session_supervisor(name)},
      {DynamicSupervisor, strategy: :one_for_one, name: Names.lease_supervisor(name)},
      {Task.Supervisor, name: Names.cleanup_supervisor(name)},
      {Manager,
       opts
       |> Keyword.put(:process_name, Names.manager(name))
       |> Keyword.put(:pool_tree, self())
       |> Keyword.put(:session_supervisor, Names.session_supervisor(name))
       |> Keyword.put(:lease_supervisor, Names.lease_supervisor(name))
       |> Keyword.put(:cleanup_supervisor, Names.cleanup_supervisor(name))}
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end

  defp stop_tree(pid) do
    case DynamicSupervisor.terminate_child(Jido.Browser.WarmPool.Supervisor, pid) do
      :ok -> :ok
      {:error, :not_found} -> Supervisor.stop(pid, :normal, 30_000)
    end
  end
end
