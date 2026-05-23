defmodule Jido.Browser.Adapters.Lightpanda.PoolRuntime do
  @moduledoc false
  @behaviour Jido.Browser.WarmPool.Runtime

  alias Jido.Browser.Adapters.Lightpanda

  @impl true
  def start_worker(%{worker_opts: worker_opts}) do
    session_id = "lightpanda-pool-#{System.unique_integer([:positive])}"

    with {:ok, connection} <- Lightpanda.start_connection(worker_opts) do
      {:ok,
       connection
       |> Map.put(:session_id, session_id)
       |> Map.put(:runtime, %{
         transport: :light_cdp,
         session_id: session_id
       })}
    end
  end

  @impl true
  def command(_worker_state, _payload, _timeout), do: {:error, :unsupported}

  @impl true
  def shutdown_worker(worker_state) do
    Lightpanda.stop_connection(worker_state)
  end

  @impl true
  def health_check(worker_state) do
    cond do
      not File.exists?(worker_state.binary) -> {:error, :binary_missing}
      not connection_alive?(worker_state.cdp_session) -> {:error, :connection_closed}
      true -> :ok
    end
  end

  defp connection_alive?(cdp_session) do
    case Map.get(cdp_session, :conn) do
      pid when is_pid(pid) -> Process.alive?(pid)
      _other -> true
    end
  end
end
