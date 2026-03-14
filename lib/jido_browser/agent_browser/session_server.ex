defmodule Jido.Browser.AgentBrowser.SessionServer do
  @moduledoc false

  use GenServer

  alias Jido.Browser.AgentBrowser.Runtime

  @startup_attempts 50
  @startup_interval 100
  @retry_attempts 3
  @retry_sleep 200

  defstruct [
    :session_id,
    :binary,
    :port,
    :endpoint,
    :stderr,
    :current_url,
    :closing,
    opts: []
  ]

  @type t :: %__MODULE__{
          session_id: String.t() | nil,
          binary: String.t() | nil,
          port: port() | nil,
          endpoint: map() | nil,
          stderr: String.t() | nil,
          current_url: String.t() | nil,
          closing: boolean() | nil,
          opts: keyword()
        }

  @type state :: t()

  @doc false
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    session_id = Keyword.fetch!(opts, :session_id)

    GenServer.start_link(__MODULE__, opts, name: {:via, Registry, {Jido.Browser.AgentBrowser.Registry, session_id}})
  end

  @doc false
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id: {__MODULE__, Keyword.fetch!(opts, :session_id)},
      start: {__MODULE__, :start_link, [opts]},
      restart: :temporary
    }
  end

  @doc false
  @spec metadata(pid()) :: map()
  def metadata(pid), do: GenServer.call(pid, :metadata)

  @doc false
  @spec command(pid(), map(), pos_integer()) :: {:ok, map()} | {:error, term()}
  def command(pid, payload, timeout) do
    GenServer.call(pid, {:command, payload, timeout}, timeout + 1_000)
  end

  @doc false
  @spec shutdown(pid()) :: :ok | {:error, term()}
  def shutdown(pid), do: GenServer.call(pid, :shutdown, 10_000)

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    session_id = Keyword.fetch!(opts, :session_id)
    binary = Keyword.fetch!(opts, :binary)
    endpoint = Runtime.endpoint(session_id)

    state = %__MODULE__{
      session_id: session_id,
      binary: binary,
      endpoint: endpoint,
      stderr: "",
      closing: false,
      opts: opts
    }

    with :ok <- ensure_socket_dir(),
         {:ok, port, stderr} <- start_daemon(state),
         {:ok, current_url, stderr} <- wait_for_ready(%{state | port: port, stderr: stderr}) do
      {:ok, %{state | port: port, stderr: stderr, current_url: current_url}}
    else
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_call(:metadata, _from, state) do
    {:reply, Runtime.session_runtime_metadata(state.session_id, self()), state}
  end

  def handle_call({:command, payload, timeout}, _from, state) do
    case dispatch(payload, timeout, state, @retry_attempts) do
      {:ok, data} ->
        current_url = Map.get(data, "url", state.current_url)
        {:reply, {:ok, data}, %{state | current_url: current_url}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:shutdown, _from, state) do
    _ = dispatch(%{"action" => "close"}, 5_000, state, 1)
    {:stop, :normal, :ok, %{state | closing: true}}
  end

  @impl true
  def handle_info({_port, {:data, data}}, state) do
    {:noreply, %{state | stderr: state.stderr <> data}}
  end

  def handle_info({_port, {:exit_status, _code}}, %{closing: true} = state) do
    {:noreply, state}
  end

  def handle_info({_port, {:exit_status, code}}, state) do
    {:stop, {:daemon_exit, code, String.trim(state.stderr)}, state}
  end

  @impl true
  def terminate(_reason, %{closing: true}), do: :ok

  def terminate(_reason, state) do
    _ = dispatch(%{"action" => "close"}, 2_000, state, 1)
    :ok
  end

  defp ensure_socket_dir do
    File.mkdir_p(Runtime.socket_dir())
  end

  defp start_daemon(state) do
    env =
      state.session_id
      |> Runtime.daemon_env(state.opts)
      |> Enum.map(fn {key, value} ->
        {String.to_charlist(key), String.to_charlist(value)}
      end)

    port =
      Port.open({:spawn_executable, state.binary}, [
        :binary,
        :exit_status,
        :hide,
        :stderr_to_stdout,
        args: [],
        env: env
      ])

    {:ok, port, ""}
  rescue
    error ->
      {:error, "Failed to start agent-browser daemon: #{Exception.message(error)}"}
  end

  defp wait_for_ready(state), do: wait_for_ready(state, @startup_attempts)

  defp wait_for_ready(state, 0) do
    {:error, "agent-browser daemon failed to start for session #{state.session_id}: #{String.trim(state.stderr)}"}
  end

  defp wait_for_ready(state, attempts) do
    case ping(state) do
      {:ok, data} ->
        {:ok, Map.get(data, "url"), state.stderr}

      {:error, _reason} ->
        receive do
          {port, {:data, data}} when port == state.port ->
            wait_for_ready(%{state | stderr: state.stderr <> data}, attempts - 1)

          {port, {:exit_status, code}} when port == state.port ->
            {:error, "agent-browser daemon exited with #{code}: #{String.trim(state.stderr)}"}
        after
          @startup_interval ->
            wait_for_ready(state, attempts - 1)
        end
    end
  end

  defp ping(state) do
    payload = %{"id" => Runtime.request_id(), "action" => "title"}

    case do_dispatch(payload, Runtime.default_daemon_timeout(), state) do
      {:ok, data} -> {:ok, data}
      {:error, _reason} -> {:error, :not_ready}
    end
  end

  defp dispatch(payload, timeout, state, attempts_left) do
    payload = Map.put_new(payload, "id", Runtime.request_id())

    case do_dispatch(payload, timeout, state) do
      {:ok, _data} = ok ->
        ok

      {:error, reason} ->
        if attempts_left > 1 and transient_error?(reason) do
          Process.sleep(@retry_sleep)
          dispatch(payload, timeout, state, attempts_left - 1)
        else
          {:error, reason}
        end
    end
  end

  defp do_dispatch(payload, timeout, state) do
    case Runtime.connect(state.session_id, Runtime.default_daemon_timeout()) do
      {:ok, socket} ->
        try do
          case send_payload(socket, payload, timeout) do
            {:ok, response} ->
              normalize_response(response)

            {:error, reason} ->
              {:error, normalize_error(reason)}
          end
        after
          :gen_tcp.close(socket)
        end

      {:error, reason} ->
        {:error, normalize_error(reason)}
    end
  end

  defp normalize_response(%{"success" => true, "data" => data}) when is_map(data), do: {:ok, data}
  defp normalize_response(%{"success" => true, "data" => nil}), do: {:ok, %{}}
  defp normalize_response(%{"success" => false, "error" => error}), do: {:error, error}
  defp normalize_response(%{"error" => error}), do: {:error, error}
  defp normalize_response(other), do: {:error, "Invalid response: #{inspect(other)}"}

  defp send_payload(socket, payload, timeout) do
    with :ok <- :gen_tcp.send(socket, Jason.encode!(payload) <> "\n"),
         {:ok, line} <- :gen_tcp.recv(socket, 0, timeout),
         {:ok, response} <- Jason.decode(line) do
      {:ok, response}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp normalize_error(:timeout), do: "Timed out waiting for daemon response"
  defp normalize_error(reason) when is_atom(reason), do: :inet.format_error(reason) |> List.to_string()
  defp normalize_error(reason), do: reason

  defp transient_error?(reason) when is_binary(reason) do
    Enum.any?(
      [
        "temporarily unavailable",
        "would block",
        "connection refused",
        "closed",
        "no such file",
        "timeout"
      ],
      &String.contains?(String.downcase(reason), &1)
    )
  end

  defp transient_error?(_reason), do: false
end
