defmodule Jido.Browser.AgentBrowser.PoolLease do
  @moduledoc false

  use GenServer

  defstruct [
    :owner,
    :owner_ref,
    :pool,
    :runtime_module,
    :checkout_timeout,
    :task_pid,
    :task_ref,
    :worker_state,
    :failed_reason,
    :pending_shutdown_from,
    waiters: [],
    closing: false
  ]

  @type t :: %__MODULE__{
          owner: pid() | nil,
          owner_ref: reference() | nil,
          pool: pid() | nil,
          runtime_module: module() | nil,
          checkout_timeout: timeout() | nil,
          task_pid: pid() | nil,
          task_ref: reference() | nil,
          worker_state: map() | nil,
          failed_reason: term(),
          pending_shutdown_from: GenServer.from() | nil,
          waiters: [GenServer.from()],
          closing: boolean()
        }

  @type state :: %__MODULE__{}

  @doc false
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc false
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id: {__MODULE__, System.unique_integer([:positive])},
      start: {__MODULE__, :start_link, [opts]},
      restart: :temporary
    }
  end

  @doc false
  @spec await_ready(pid(), timeout()) :: {:ok, map()} | {:error, term()}
  def await_ready(pid, timeout) do
    GenServer.call(pid, :await_ready, timeout)
  end

  @doc false
  @spec command(pid(), map(), pos_integer()) :: {:ok, map()} | {:error, term()}
  def command(pid, payload, timeout) do
    GenServer.call(pid, {:command, payload, timeout}, timeout + 1_000)
  catch
    :exit, reason ->
      {:error, normalize_command_exit(reason)}
  end

  @doc false
  @spec shutdown(pid()) :: :ok | {:error, term()}
  def shutdown(pid) do
    GenServer.call(pid, :shutdown, 10_000)
  catch
    :exit, reason ->
      normalize_shutdown_exit(reason)
  end

  @doc false
  @spec force_shutdown(pid()) :: :ok | {:error, term()}
  def force_shutdown(pid) do
    GenServer.call(pid, :force_shutdown, 10_000)
  catch
    :exit, reason ->
      normalize_shutdown_exit(reason)
  end

  @impl true
  def init(opts) do
    owner = Keyword.fetch!(opts, :owner)
    pool = Keyword.fetch!(opts, :pool)
    runtime_module = Keyword.fetch!(opts, :runtime_module)
    checkout_timeout = Keyword.fetch!(opts, :checkout_timeout)

    state = %__MODULE__{
      owner: owner,
      owner_ref: Process.monitor(owner),
      pool: pool,
      runtime_module: runtime_module,
      checkout_timeout: checkout_timeout
    }

    {:ok, state, {:continue, :checkout}}
  end

  @impl true
  def handle_continue(:checkout, state) do
    lease = self()

    {:ok, task_pid} =
      Task.start(fn ->
        hold_checkout(lease, state.pool, state.checkout_timeout)
      end)

    {:noreply, %{state | task_pid: task_pid, task_ref: Process.monitor(task_pid)}}
  end

  @impl true
  def handle_call(:await_ready, _from, %{worker_state: worker_state} = state) when is_map(worker_state) do
    {:reply, {:ok, worker_state}, state}
  end

  def handle_call(:await_ready, _from, %{failed_reason: reason} = state) when not is_nil(reason) do
    {:reply, {:error, reason}, state}
  end

  def handle_call(:await_ready, from, state) do
    {:noreply, %{state | waiters: [from | state.waiters]}}
  end

  def handle_call({:command, _payload, _timeout}, _from, %{closing: true} = state) do
    {:reply, {:error, :lease_closing}, state}
  end

  def handle_call(
        {:command, payload, timeout},
        {owner, _ref},
        %{worker_state: worker_state, runtime_module: runtime_module} = state
      )
      when is_map(worker_state) and owner == state.owner do
    {:reply, runtime_module.command(worker_state, payload, timeout), state}
  end

  def handle_call({:command, _payload, _timeout}, {_owner, _ref}, %{owner: owner} = state) do
    {:reply, {:error, {:not_owner, owner}}, state}
  end

  def handle_call({:command, _payload, _timeout}, _from, %{failed_reason: reason} = state) when not is_nil(reason) do
    {:reply, {:error, reason}, state}
  end

  def handle_call({:command, _payload, _timeout}, _from, state) do
    {:reply, {:error, :lease_not_ready}, state}
  end

  def handle_call(request, from, %{closing: true} = state) when request in [:shutdown, :force_shutdown] do
    GenServer.reply(from, :ok)
    {:noreply, state}
  end

  def handle_call(:shutdown, {owner, _ref}, %{owner: owner, task_pid: nil} = state) do
    {:stop, :normal, :ok, state}
  end

  def handle_call(:shutdown, {owner, _ref} = from, %{owner: owner} = state) do
    send(state.task_pid, {:release, :recycle})
    {:noreply, %{state | closing: true, pending_shutdown_from: from}}
  end

  def handle_call(:shutdown, {_owner, _ref}, %{owner: owner} = state) do
    {:reply, {:error, {:not_owner, owner}}, state}
  end

  def handle_call(:force_shutdown, _from, %{task_pid: nil} = state) do
    {:stop, :normal, :ok, state}
  end

  def handle_call(request, from, state) when request in [:shutdown, :force_shutdown] do
    send(state.task_pid, {:release, :recycle})
    {:noreply, %{state | closing: true, pending_shutdown_from: from}}
  end

  @impl true
  def handle_info({:checkout_ready, task_pid, worker_state}, %{task_pid: task_pid} = state) do
    Enum.each(state.waiters, &GenServer.reply(&1, {:ok, worker_state}))
    {:noreply, %{state | worker_state: worker_state, waiters: []}}
  end

  def handle_info({:checkout_failed, task_pid, reason}, %{task_pid: task_pid} = state) do
    Enum.each(state.waiters, &GenServer.reply(&1, {:error, reason}))
    {:noreply, %{state | failed_reason: reason, waiters: []}}
  end

  def handle_info({:DOWN, owner_ref, :process, _pid, _reason}, %{owner_ref: owner_ref, task_pid: task_pid} = state)
      when is_pid(task_pid) do
    send(task_pid, {:release, :recycle})
    {:stop, :normal, %{state | closing: true}}
  end

  def handle_info({:DOWN, owner_ref, :process, _pid, _reason}, %{owner_ref: owner_ref} = state) do
    {:stop, :normal, state}
  end

  def handle_info({:DOWN, task_ref, :process, _pid, reason}, %{task_ref: task_ref} = state) do
    Enum.each(state.waiters, &GenServer.reply(&1, {:error, normalize_task_reason(reason)}))
    failed_reason = state.failed_reason || normalize_task_reason(reason)

    cond do
      state.pending_shutdown_from ->
        GenServer.reply(state.pending_shutdown_from, :ok)
        {:stop, :normal, %{state | waiters: []}}

      state.closing ->
        {:stop, :normal, %{state | waiters: []}}

      true ->
        {:noreply, %{state | failed_reason: failed_reason, waiters: [], task_pid: nil, task_ref: nil}}
    end
  end

  defp hold_checkout(owner, pool, checkout_timeout) do
    NimblePool.checkout!(
      pool,
      :lease,
      fn _from, worker_state ->
        send(owner, {:checkout_ready, self(), worker_state})
        owner_ref = Process.monitor(owner)
        {:ok, await_release(owner_ref)}
      end,
      checkout_timeout
    )
  catch
    :exit, reason ->
      send(owner, {:checkout_failed, self(), normalize_checkout_reason(reason)})
  end

  defp await_release(owner_ref) do
    receive do
      {:release, reason} ->
        Process.demonitor(owner_ref, [:flush])
        reason

      {:DOWN, ^owner_ref, :process, _pid, _reason} ->
        :recycle
    end
  end

  defp normalize_checkout_reason({:timeout, _call}), do: :checkout_timeout
  defp normalize_checkout_reason(reason), do: reason

  defp normalize_command_exit({:timeout, {GenServer, :call, _call}}), do: :lease_timeout
  defp normalize_command_exit({:noproc, {GenServer, :call, _call}}), do: :lease_unavailable
  defp normalize_command_exit({:normal, {GenServer, :call, _call}}), do: :lease_unavailable
  defp normalize_command_exit(reason), do: reason

  defp normalize_shutdown_exit({:timeout, {GenServer, :call, _call}}), do: {:error, :lease_timeout}
  defp normalize_shutdown_exit({:noproc, {GenServer, :call, _call}}), do: :ok
  defp normalize_shutdown_exit({:normal, {GenServer, :call, _call}}), do: :ok
  defp normalize_shutdown_exit(reason), do: {:error, reason}

  defp normalize_task_reason(:normal), do: :lease_closed
  defp normalize_task_reason({:timeout, _call}), do: :checkout_timeout
  defp normalize_task_reason(reason), do: reason
end
