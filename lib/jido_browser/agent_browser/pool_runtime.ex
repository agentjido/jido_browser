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
  @spec start_worker(map()) :: {:ok, worker_state()} | {:error, term()}
  def start_worker(%{session_opts: session_opts, session_supervisor: session_supervisor}) do
    session_id = Uniq.UUID.uuid4()

    child_spec =
      {SessionServer,
       session_opts
       |> Keyword.put(:session_id, session_id)
       |> Keyword.put(:registration, :none)}

    case DynamicSupervisor.start_child(session_supervisor, child_spec) do
      {:ok, pid} ->
        {:ok,
         %{
           session_id: session_id,
           binary: Keyword.fetch!(session_opts, :binary),
           manager: pid,
           runtime: Runtime.session_runtime_metadata(session_id, pid)
         }}

      {:error, {:already_started, pid}} ->
        {:ok,
         %{
           session_id: session_id,
           binary: Keyword.fetch!(session_opts, :binary),
           manager: pid,
           runtime: Runtime.session_runtime_metadata(session_id, pid)
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
