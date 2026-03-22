defmodule Jido.Browser.AgentBrowser.PoolWorker do
  @moduledoc false
  @behaviour NimblePool

  @impl NimblePool
  def init_pool(init_arg), do: {:ok, init_arg}

  @impl NimblePool
  def init_worker(%{manager: manager, runtime_module: runtime_module, session_opts: session_opts} = pool_state) do
    {:async,
     fn ->
       case runtime_module.start_worker(session_opts) do
         {:ok, worker_state} ->
           send(manager, {:pool_worker_ready, worker_state.session_id})
           worker_state

         {:error, reason} ->
           exit({:worker_start_failed, reason})
       end
     end, pool_state}
  end

  @impl NimblePool
  def handle_checkout(:lease, _from, worker_state, pool_state) do
    {:ok, worker_state, worker_state, pool_state}
  end

  @impl NimblePool
  def handle_checkin(:recycle, _from, worker_state, pool_state) do
    {:remove, {:recycle, worker_state.session_id}, pool_state}
  end

  @impl NimblePool
  def terminate_worker(
        _reason,
        worker_state,
        %{cleanup_supervisor: cleanup_supervisor, runtime_module: runtime_module} = pool_state
      ) do
    _ =
      Task.Supervisor.start_child(cleanup_supervisor, fn ->
        runtime_module.shutdown_worker(worker_state)
      end)

    {:ok, pool_state}
  end
end
