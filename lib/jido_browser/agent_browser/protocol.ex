defmodule Jido.Browser.AgentBrowser.Protocol do
  @moduledoc false

  import Bitwise

  alias Jido.Browser.ID

  @daemon_timeout 5_000

  @type session_opts :: keyword()

  @doc false
  @spec default_daemon_timeout() :: pos_integer()
  def default_daemon_timeout, do: @daemon_timeout

  @doc false
  @spec session_runtime_metadata(String.t(), pid()) :: map()
  def session_runtime_metadata(session_id, pid) do
    %{
      transport: :agent_browser_ipc,
      endpoint: endpoint(session_id),
      manager: pid,
      session_id: session_id
    }
  end

  @doc false
  @spec endpoint(String.t()) :: map()
  def endpoint(session_id) do
    if windows?() do
      %{type: :tcp, host: "127.0.0.1", port: port_for_session(session_id)}
    else
      %{type: :unix, path: socket_path(session_id)}
    end
  end

  @doc false
  @spec socket_dir() :: String.t()
  def socket_dir do
    cond do
      value = env("AGENT_BROWSER_SOCKET_DIR") ->
        value

      value = env("XDG_RUNTIME_DIR") ->
        Path.join(value, "agent-browser")

      home = System.user_home() ->
        Path.join(home, ".agent-browser")

      true ->
        Path.join(System.tmp_dir!(), "agent-browser")
    end
  end

  @doc false
  @spec socket_path(String.t()) :: String.t()
  def socket_path(session_id), do: Path.join(socket_dir(), "#{session_id}.sock")

  @doc false
  @spec pid_path(String.t()) :: String.t()
  def pid_path(session_id), do: Path.join(socket_dir(), "#{session_id}.pid")

  @doc false
  @spec port_path(String.t()) :: String.t()
  def port_path(session_id), do: Path.join(socket_dir(), "#{session_id}.port")

  @doc false
  @spec port_for_session(String.t()) :: pos_integer()
  def port_for_session(session_id) do
    hash =
      session_id
      |> String.to_charlist()
      |> Enum.reduce(0, fn char, acc ->
        Bitwise.band((acc <<< 5) - acc + char, 0xFFFFFFFF)
      end)

    49_152 + rem(abs(hash), 16_383)
  end

  @doc false
  @spec daemon_env(String.t(), session_opts()) :: [{String.t(), String.t()}]
  def daemon_env(session_id, opts) do
    []
    |> put_env("AGENT_BROWSER_DAEMON", "1")
    |> put_env("AGENT_BROWSER_SESSION", session_id)
    |> maybe_put_bool_env("AGENT_BROWSER_HEADED", Keyword.get(opts, :headed, false))
    |> maybe_put_bool_env("AGENT_BROWSER_DEBUG", Keyword.get(opts, :debug, false))
    |> maybe_put("AGENT_BROWSER_EXECUTABLE_PATH", Keyword.get(opts, :executable_path))
    |> maybe_put("AGENT_BROWSER_SESSION_NAME", Keyword.get(opts, :session_name))
    |> maybe_put("AGENT_BROWSER_DOWNLOAD_PATH", Keyword.get(opts, :download_path))
    |> maybe_put("AGENT_BROWSER_COLOR_SCHEME", Keyword.get(opts, :color_scheme))
    |> maybe_put("AGENT_BROWSER_ENGINE", Keyword.get(opts, :engine))
    |> maybe_put_timeout("AGENT_BROWSER_DEFAULT_TIMEOUT", Keyword.get(opts, :timeout))
    |> maybe_put_list("AGENT_BROWSER_ALLOWED_DOMAINS", Keyword.get(opts, :allowed_domains))
  end

  @doc false
  @spec request_id() :: String.t()
  def request_id, do: ID.generate()

  @doc false
  @spec connect(String.t(), pos_integer()) :: {:ok, port()} | {:error, term()}
  def connect(session_id, timeout) do
    if windows?() do
      :gen_tcp.connect(~c"127.0.0.1", port_for_session(session_id), tcp_options(), timeout)
    else
      :gen_tcp.connect({:local, socket_path(session_id)}, 0, tcp_options(), timeout)
    end
  end

  @doc false
  @spec tcp_options() :: [:binary | {:active, false} | {:packet, :line}]
  def tcp_options, do: [:binary, packet: :line, active: false]

  @doc false
  @spec windows?() :: boolean()
  def windows?, do: match?({:win32, _}, :os.type())

  @doc false
  @spec config(atom(), term()) :: term()
  def config(key, default \\ nil) do
    :jido_browser
    |> Application.get_env(:agent_browser, [])
    |> Keyword.get(key, default)
  end

  defp env(var) do
    case System.get_env(var) do
      nil -> nil
      "" -> nil
      value -> value
    end
  end

  defp put_env(acc, key, value), do: [{key, value} | acc]

  defp maybe_put(acc, _key, nil), do: acc
  defp maybe_put(acc, _key, ""), do: acc
  defp maybe_put(acc, key, value), do: [{key, to_string(value)} | acc]

  defp maybe_put_bool_env(acc, _key, false), do: acc
  defp maybe_put_bool_env(acc, key, true), do: [{key, "1"} | acc]

  defp maybe_put_timeout(acc, _key, nil), do: acc
  defp maybe_put_timeout(acc, key, timeout), do: [{key, to_string(timeout)} | acc]

  defp maybe_put_list(acc, _key, nil), do: acc
  defp maybe_put_list(acc, _key, []), do: acc
  defp maybe_put_list(acc, key, value), do: [{key, Enum.join(value, ",")} | acc]
end
