defmodule Jido.Browser.WarmPool.Worker do
  @moduledoc false
  @behaviour NimblePool

  alias Jido.Browser.WarmPool.Runtime

  @impl NimblePool
  def init_pool(init_arg), do: {:ok, init_arg}

  @impl NimblePool
  def init_worker(%{manager: manager, runtime_module: runtime_module} = pool_state) do
    {:async,
     fn ->
       case runtime_module.start_worker(pool_state) do
         {:ok, worker_state} ->
           send(manager, {:pool_worker_ready, worker_state.session_id})
           worker_state

         {:error, reason} ->
           exit({:worker_start_failed, reason})
       end
     end, pool_state}
  end

  @impl NimblePool
  def handle_checkout(:lease, _from, worker_state, %{runtime_module: runtime_module} = pool_state) do
    case Runtime.healthy?(runtime_module, worker_state) do
      :ok ->
        {:ok, worker_state, worker_state, pool_state}

      {:error, reason} ->
        {:remove, {:unhealthy, reason}, pool_state}
    end
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
    _ = start_cleanup_task(cleanup_supervisor, runtime_module, worker_state)
    {:ok, pool_state}
  end

  defp start_cleanup_task(cleanup_supervisor, runtime_module, worker_state) do
    Task.Supervisor.start_child(cleanup_supervisor, fn ->
      runtime_module.shutdown_worker(worker_state)
    end)
  catch
    :exit, _reason ->
      Task.start(fn ->
        runtime_module.shutdown_worker(worker_state)
      end)
  end
end
