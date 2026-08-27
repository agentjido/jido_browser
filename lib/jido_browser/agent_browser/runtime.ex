defmodule Jido.Browser.AgentBrowser.Runtime do
  @moduledoc false

  alias Jido.Browser.AgentBrowser.Binary
  alias Jido.Browser.AgentBrowser.Protocol
  alias Jido.Browser.Application, as: BrowserApplication
  alias Jido.Browser.Installer.Paths

  @command_timeout 30_000

  @type session_opts :: keyword()

  @capabilities %{
    snapshot: true,
    refs: true,
    waits: true,
    state: true,
    tabs: true,
    diagnostics: true
  }

  @doc false
  @spec supported_version() :: String.t()
  defdelegate supported_version(), to: Binary

  @doc false
  @spec default_command_timeout() :: pos_integer()
  def default_command_timeout, do: @command_timeout

  @doc false
  @spec default_daemon_timeout() :: pos_integer()
  defdelegate default_daemon_timeout(), to: Protocol

  @doc false
  @spec capabilities() :: map()
  def capabilities, do: @capabilities

  @doc false
  @spec find_binary() :: {:ok, String.t()} | {:error, term()}
  def find_binary, do: Binary.resolve(Paths.agent_browser_package_path())

  @doc false
  @spec ensure_supported_version(String.t()) :: :ok | {:error, term()}
  defdelegate ensure_supported_version(binary), to: Binary

  @doc false
  @spec parse_version(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  defdelegate parse_version(output), to: Binary

  @doc false
  @spec ensure_session_server(String.t(), session_opts()) :: {:ok, pid(), map()} | {:error, term()}
  def ensure_session_server(session_id, opts) do
    with :ok <- BrowserApplication.ensure_started() do
      do_ensure_session_server(session_id, opts, 1)
    end
  end

  @doc false
  @spec lookup_session_server(String.t()) :: {:ok, pid()} | :error
  def lookup_session_server(session_id) do
    case safe_registry_lookup(Jido.Browser.AgentBrowser.Registry, session_id) do
      [{pid, _value}] -> {:ok, pid}
      [] -> :error
    end
  end

  @doc false
  @spec session_runtime_metadata(String.t(), pid()) :: map()
  defdelegate session_runtime_metadata(session_id, pid), to: Protocol

  @doc false
  @spec endpoint(String.t()) :: map()
  defdelegate endpoint(session_id), to: Protocol

  @doc false
  @spec socket_dir() :: String.t()
  defdelegate socket_dir(), to: Protocol

  @doc false
  @spec socket_path(String.t()) :: String.t()
  defdelegate socket_path(session_id), to: Protocol

  @doc false
  @spec pid_path(String.t()) :: String.t()
  defdelegate pid_path(session_id), to: Protocol

  @doc false
  @spec port_path(String.t()) :: String.t()
  defdelegate port_path(session_id), to: Protocol

  @doc false
  @spec port_for_session(String.t()) :: pos_integer()
  defdelegate port_for_session(session_id), to: Protocol

  @doc false
  @spec daemon_env(String.t(), session_opts()) :: [{String.t(), String.t()}]
  defdelegate daemon_env(session_id, opts), to: Protocol

  @doc false
  @spec request_id() :: String.t()
  defdelegate request_id(), to: Protocol

  @doc false
  @spec connect(String.t(), pos_integer()) :: {:ok, port()} | {:error, term()}
  defdelegate connect(session_id, timeout), to: Protocol

  @doc false
  @spec tcp_options() :: [:binary | {:active, false} | {:packet, :line}]
  defdelegate tcp_options(), to: Protocol

  @doc false
  @spec windows?() :: boolean()
  defdelegate windows?(), to: Protocol

  @doc false
  @spec config(atom(), term()) :: term()
  def config(key, default \\ nil), do: Protocol.config(key, default)

  defp do_ensure_session_server(session_id, opts, retries_left) do
    case lookup_session_server(session_id) do
      {:ok, pid} ->
        {:ok, pid, session_runtime_metadata(session_id, pid)}

      :error ->
        child_spec = {Jido.Browser.AgentBrowser.SessionServer, Keyword.put(opts, :session_id, session_id)}

        try do
          case DynamicSupervisor.start_child(Jido.Browser.AgentBrowser.SessionSupervisor, child_spec) do
            {:ok, pid} ->
              {:ok, pid, session_runtime_metadata(session_id, pid)}

            {:error, {:already_started, pid}} ->
              {:ok, pid, session_runtime_metadata(session_id, pid)}

            {:error, reason} ->
              {:error, reason}
          end
        catch
          :exit, reason ->
            retry_ensure_session_server(reason, session_id, opts, retries_left)
        end
    end
  end

  defp retry_ensure_session_server(reason, _session_id, _opts, 0), do: {:error, reason}

  defp retry_ensure_session_server(_reason, session_id, opts, retries_left) do
    with :ok <- BrowserApplication.ensure_started() do
      do_ensure_session_server(session_id, opts, retries_left - 1)
    end
  end

  defp safe_registry_lookup(registry, key) do
    Registry.lookup(registry, key)
  catch
    :exit, _reason ->
      []
  end
end
