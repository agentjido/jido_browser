defmodule Jido.Browser.Adapters.Lightpanda.PoolRuntime do
  @moduledoc false
  @behaviour Jido.Browser.WarmPool.Runtime

  alias Jido.Browser.Adapters.Lightpanda

  @impl true
  @spec start_worker(map()) :: {:ok, map()} | {:error, term()}
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
  @spec command(map(), term(), timeout()) :: {:error, :unsupported}
  def command(_worker_state, _payload, _timeout), do: {:error, :unsupported}

  @impl true
  @spec shutdown_worker(map()) :: :ok | {:error, term()}
  def shutdown_worker(worker_state) do
    Lightpanda.stop_connection(worker_state)
  end

  @impl true
  @spec health_check(map()) :: :ok | {:error, atom()}
  def health_check(worker_state) do
    cond do
      not File.exists?(worker_state.binary) -> {:error, :binary_missing}
      not connection_alive?(worker_state.cdp_session) -> {:error, :connection_closed}
      not page_healthy?(worker_state) -> {:error, :page_unavailable}
      true -> :ok
    end
  end

  defp connection_alive?(cdp_session) do
    case Map.get(cdp_session, :conn) do
      pid when is_pid(pid) -> Process.alive?(pid)
      _other -> true
    end
  end

  defp page_healthy?(%{page_module: page_module, page: page}) do
    case page_module.content(page) do
      {:ok, _content} -> true
      _other -> false
    end
  rescue
    _error -> false
  catch
    _kind, _reason -> false
  end

  defp page_healthy?(_worker_state), do: true
end
