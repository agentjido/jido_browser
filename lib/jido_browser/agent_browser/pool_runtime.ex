defmodule Jido.Browser.AgentBrowser.PoolRuntime do
  @moduledoc false

  alias Jido.Browser.AgentBrowser.Runtime
  alias Jido.Browser.AgentBrowser.SessionServer

  @type worker_state :: %{
          session_id: String.t(),
          binary: String.t(),
          manager: pid(),
          runtime: map()
        }

  @doc false
  @spec start_worker(keyword()) :: {:ok, worker_state()} | {:error, term()}
  def start_worker(session_opts) do
    session_id = Uniq.UUID.uuid4()

    case Runtime.ensure_session_server(session_id, session_opts) do
      {:ok, pid, runtime} ->
        {:ok,
         %{
           session_id: session_id,
           binary: Keyword.fetch!(session_opts, :binary),
           manager: pid,
           runtime: runtime
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc false
  @spec command(worker_state(), map(), pos_integer()) :: {:ok, map()} | {:error, term()}
  def command(%{manager: pid}, payload, timeout) when is_pid(pid) do
    SessionServer.command(pid, payload, timeout)
  catch
    :exit, reason ->
      {:error, reason}
  end

  @doc false
  @spec shutdown_worker(worker_state()) :: :ok | {:error, term()}
  def shutdown_worker(%{manager: pid}) when is_pid(pid) do
    if Process.alive?(pid) do
      SessionServer.shutdown(pid)
    else
      :ok
    end
  catch
    :exit, _reason ->
      :ok
  end
end
