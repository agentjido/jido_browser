defmodule Jido.Browser.AgentBrowser.PoolManager do
  @moduledoc false

  use GenServer

  alias Jido.Browser.AgentBrowser.PoolLease
  alias Jido.Browser.AgentBrowser.PoolRuntime
  alias Jido.Browser.AgentBrowser.PoolWorker

  defstruct [
    :name,
    :size,
    :pool_pid,
    :runtime_module,
    :startup_ready,
    ready_count: 0,
    waiters: [],
    lease_refs: %{},
    stopping: false
  ]

  @type t :: %__MODULE__{
          name: term(),
          size: pos_integer() | nil,
          pool_pid: pid() | nil,
          runtime_module: module() | nil,
          startup_ready: boolean() | nil,
          ready_count: non_neg_integer(),
          waiters: [GenServer.from()],
          lease_refs: %{reference() => pid()},
          stopping: boolean()
        }

  @type state :: %__MODULE__{}

  @doc false
  @spec start_pool(keyword()) :: DynamicSupervisor.on_start_child()
  def start_pool(opts) do
    child_spec = {__MODULE__, opts}
    DynamicSupervisor.start_child(Jido.Browser.AgentBrowser.PoolSupervisor, child_spec)
  end

  @doc false
  @spec stop_pool(term()) :: :ok | {:error, term()}
  def stop_pool(pool) do
    with {:ok, pid} <- resolve(pool) do
      GenServer.call(pid, :stop_pool, 30_000)
    end
  catch
    :exit, reason ->
      {:error, reason}
  end

  @doc false
  @spec await_ready(pid(), timeout()) :: :ok
  def await_ready(pid, timeout) do
    GenServer.call(pid, :await_ready, timeout)
  end

  @doc false
  @spec checkout_session(term(), keyword()) :: {:ok, pid(), map()} | {:error, term()}
  def checkout_session(pool, opts) do
    with {:ok, pid} <- resolve(pool),
         {:ok, pool_pid, runtime_module} <- GenServer.call(pid, :lease_config),
         {:ok, lease_pid} <- start_lease(pool_pid, runtime_module, opts),
         {:ok, worker_state} <- await_lease(lease_pid, opts) do
      GenServer.cast(pid, {:track_lease, lease_pid})
      {:ok, lease_pid, worker_state}
    end
  catch
    :exit, reason ->
      {:error, reason}
  end

  @doc false
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    process_name = Keyword.get(opts, :process_name, via(name))

    GenServer.start_link(__MODULE__, opts, name: process_name)
  end

  @doc false
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id: {__MODULE__, Keyword.fetch!(opts, :name)},
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  @impl true
  def init(opts) do
    name = Keyword.fetch!(opts, :name)
    size = Keyword.fetch!(opts, :size)
    runtime_module = Keyword.get(opts, :pool_runtime_module) || PoolRuntime
    session_opts = Keyword.fetch!(opts, :session_opts)

    {:ok, pool_pid} =
      NimblePool.start_link(
        worker:
          {PoolWorker,
           %{
             manager: self(),
             session_opts: session_opts,
             cleanup_supervisor: Jido.Browser.AgentBrowser.CleanupSupervisor,
             runtime_module: runtime_module
           }},
        pool_size: size
      )

    {:ok,
     %__MODULE__{
       name: name,
       size: size,
       pool_pid: pool_pid,
       runtime_module: runtime_module,
       startup_ready: false
     }}
  end

  @impl true
  def handle_call(:await_ready, _from, %{startup_ready: true} = state) do
    {:reply, :ok, state}
  end

  def handle_call(:await_ready, from, state) do
    {:noreply, %{state | waiters: [from | state.waiters]}}
  end

  def handle_call(:lease_config, _from, %{stopping: true} = state) do
    {:reply, {:error, :pool_stopping}, state}
  end

  def handle_call(:lease_config, _from, state) do
    {:reply, {:ok, state.pool_pid, state.runtime_module}, state}
  end

  def handle_call(:stop_pool, _from, state) do
    Enum.each(Map.values(state.lease_refs), &PoolLease.force_shutdown/1)
    {:stop, :normal, :ok, %{state | stopping: true}}
  end

  @impl true
  def handle_cast({:track_lease, lease_pid}, state) do
    monitor_ref = Process.monitor(lease_pid)
    {:noreply, %{state | lease_refs: Map.put(state.lease_refs, monitor_ref, lease_pid)}}
  end

  @impl true
  def handle_info({:pool_worker_ready, _session_id}, %{startup_ready: true} = state) do
    {:noreply, state}
  end

  def handle_info({:pool_worker_ready, _session_id}, state) do
    ready_count = state.ready_count + 1
    startup_ready = ready_count >= state.size

    if startup_ready do
      Enum.each(state.waiters, &GenServer.reply(&1, :ok))
    end

    {:noreply,
     %{
       state
       | ready_count: ready_count,
         startup_ready: startup_ready,
         waiters: if(startup_ready, do: [], else: state.waiters)
     }}
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    {:noreply, %{state | lease_refs: Map.delete(state.lease_refs, ref)}}
  end

  @impl true
  def terminate(_reason, state) do
    Enum.each(Map.values(state.lease_refs), &PoolLease.force_shutdown/1)
    :ok
  end

  @doc false
  @spec resolve(term()) :: {:ok, pid()} | {:error, term()}
  def resolve(pid) when is_pid(pid), do: {:ok, pid}

  def resolve(name) do
    case Registry.lookup(Jido.Browser.AgentBrowser.PoolRegistry, name) do
      [{pid, _value}] -> {:ok, pid}
      [] -> resolve_process_name(name)
    end
  end

  defp via(name), do: {:via, Registry, {Jido.Browser.AgentBrowser.PoolRegistry, name}}

  defp resolve_process_name(name) when is_atom(name) do
    case Process.whereis(name) do
      pid when is_pid(pid) -> {:ok, pid}
      nil -> {:error, :pool_not_found}
    end
  end

  defp resolve_process_name({:global, _term} = name) do
    case GenServer.whereis(name) do
      pid when is_pid(pid) -> {:ok, pid}
      nil -> {:error, :pool_not_found}
    end
  end

  defp resolve_process_name({:via, _module, _term} = name) do
    case GenServer.whereis(name) do
      pid when is_pid(pid) -> {:ok, pid}
      nil -> {:error, :pool_not_found}
    end
  end

  defp resolve_process_name(_name), do: {:error, :pool_not_found}

  defp start_lease(pool_pid, runtime_module, opts) do
    checkout_timeout = Keyword.get(opts, :checkout_timeout, 5_000)
    owner = Keyword.fetch!(opts, :owner)

    DynamicSupervisor.start_child(
      Jido.Browser.AgentBrowser.LeaseSupervisor,
      {PoolLease, owner: owner, pool: pool_pid, runtime_module: runtime_module, checkout_timeout: checkout_timeout}
    )
  end

  defp await_lease(lease_pid, opts) do
    checkout_timeout = Keyword.get(opts, :checkout_timeout, 5_000)

    case PoolLease.await_ready(lease_pid, checkout_timeout + 1_000) do
      {:ok, worker_state} ->
        {:ok, worker_state}

      {:error, reason} ->
        _ = PoolLease.force_shutdown(lease_pid)
        {:error, reason}
    end
  end
end
