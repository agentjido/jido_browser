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
           worker_state = initialize_pool_metadata(worker_state)
           send(manager, {:pool_worker_ready, worker_state.session_id})
           worker_state

         {:error, reason} ->
           send(manager, {:pool_worker_start_failed, reason})
           exit({:worker_start_failed, reason})
       end
     end, pool_state}
  end

  @impl NimblePool
  def handle_checkout(:lease, _from, worker_state, %{manager: manager, runtime_module: runtime_module} = pool_state) do
    case Runtime.healthy?(runtime_module, worker_state) do
      :ok ->
        worker_state = increment_uses(worker_state)
        send(manager, {:pool_worker_checked_out, worker_state.session_id})
        {:ok, worker_state, worker_state, pool_state}

      {:error, reason} ->
        {:remove, {:unhealthy, reason}, pool_state}
    end
  end

  @impl NimblePool
  def handle_checkin(:recycle, _from, worker_state, pool_state) do
    {:remove, {:recycle, worker_state.session_id}, pool_state}
  end

  def handle_checkin(:checkin, _from, worker_state, %{manager: manager, runtime_module: runtime_module} = pool_state) do
    case Runtime.healthy?(runtime_module, worker_state) do
      :ok ->
        case reusable?(worker_state, pool_state) do
          :ok ->
            send(manager, {:pool_worker_checked_in, worker_state.session_id})
            {:ok, worker_state, pool_state}

          {:error, reason} ->
            {:remove, reason, pool_state}
        end

      {:error, reason} ->
        {:remove, {:unhealthy, reason}, pool_state}
    end
  end

  @impl NimblePool
  def terminate_worker(
        reason,
        worker_state,
        %{cleanup_supervisor: cleanup_supervisor, manager: manager, runtime_module: runtime_module} = pool_state
      ) do
    send(manager, {:pool_worker_removed, worker_state.session_id, reason})
    _ = start_cleanup_task(cleanup_supervisor, runtime_module, worker_state)
    {:ok, pool_state}
  end

  defp initialize_pool_metadata(worker_state) do
    worker_state
    |> Map.put_new(:pool_started_at_ms, System.monotonic_time(:millisecond))
    |> Map.put_new(:pool_uses, 0)
  end

  defp increment_uses(worker_state) do
    Map.update(worker_state, :pool_uses, 1, &(&1 + 1))
  end

  defp reusable?(worker_state, pool_state) do
    cond do
      max_uses_exceeded?(worker_state, pool_state) ->
        {:error, {:max_uses, worker_state.session_id, pool_state.max_uses}}

      max_age_exceeded?(worker_state, pool_state) ->
        {:error, {:max_age_ms, worker_state.session_id, pool_state.max_age_ms}}

      true ->
        :ok
    end
  end

  defp max_uses_exceeded?(_worker_state, %{max_uses: nil}), do: false

  defp max_uses_exceeded?(worker_state, %{max_uses: max_uses}) do
    Map.get(worker_state, :pool_uses, 0) >= max_uses
  end

  defp max_age_exceeded?(_worker_state, %{max_age_ms: nil}), do: false

  defp max_age_exceeded?(worker_state, %{max_age_ms: max_age_ms}) do
    System.monotonic_time(:millisecond) - Map.fetch!(worker_state, :pool_started_at_ms) >= max_age_ms
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
