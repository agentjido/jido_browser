defmodule Jido.Browser.TestPoolRuntime.Worker do
  @moduledoc false

  use GenServer

  def start_link(session_id) do
    GenServer.start_link(__MODULE__, session_id)
  end

  @impl true
  def init(session_id) do
    {:ok, %{session_id: session_id, current_url: nil}}
  end

  @impl true
  def handle_call({:command, %{"action" => "navigate", "url" => "fail://page"}}, _from, state) do
    {:reply, {:error, :navigation_failed}, state}
  end

  def handle_call({:command, %{"action" => "navigate", "url" => "crash://daemon"}}, _from, state) do
    {:stop, :normal, {:error, :transport_closed}, state}
  end

  def handle_call({:command, %{"action" => "navigate", "url" => url}}, _from, state) do
    {:reply, {:ok, %{"url" => url}}, %{state | current_url: url}}
  end

  def handle_call({:command, %{"action" => "title"}}, _from, state) do
    title =
      case state.current_url do
        nil -> "Blank"
        url -> "Title for #{url}"
      end

    {:reply, {:ok, %{"title" => title}}, state}
  end

  def handle_call({:command, %{"action" => "close"}}, _from, state) do
    {:stop, :normal, {:ok, %{}}, state}
  end

  def handle_call({:command, _payload}, _from, state) do
    {:reply, {:ok, %{}}, state}
  end
end

defmodule Jido.Browser.TestPoolRuntime do
  @moduledoc false
  @behaviour Jido.Browser.WarmPool.Runtime

  alias Jido.Browser.TestPoolRuntime.Worker

  def start_worker(%{worker_opts: opts}), do: start_worker(opts)

  def start_worker(opts) do
    Process.sleep(Keyword.get(opts, :worker_init_delay, 0))

    session_id = "pool-#{System.unique_integer([:positive])}"
    {:ok, pid} = Worker.start_link(session_id)

    {:ok,
     %{
       session_id: session_id,
       binary: Keyword.get(opts, :binary, "/fake/agent-browser"),
       manager: pid,
       runtime: %{
         transport: :test_pool,
         endpoint: %{type: :test},
         session_id: session_id
       }
     }}
  end

  def command(%{manager: pid}, payload, timeout) do
    GenServer.call(pid, {:command, payload}, timeout)
  catch
    :exit, _reason ->
      {:error, :worker_down}
  end

  def shutdown_worker(%{manager: pid}) do
    if Process.alive?(pid) do
      GenServer.stop(pid, :normal, 5_000)
    else
      :ok
    end
  catch
    :exit, _reason ->
      :ok
  end

  def health_check(%{manager: pid}) when is_pid(pid) do
    if Process.alive?(pid), do: :ok, else: {:error, :worker_down}
  end
end
