defmodule Jido.Browser.Pool do
  @moduledoc """
  Public supervised child for warm AgentBrowser session pools.

  Add `Jido.Browser.Pool` to your application's supervision tree when you want a
  pool to start with your app and stay available by name:

      children = [
        {Jido.Browser.Pool, name: :default, size: 2, headless: true}
      ]

  After startup, check out sessions with `Jido.Browser.start_session(pool: :default)`.

  This is the recommended production path for long-lived applications. Use
  `Jido.Browser.start_pool/1` for scripts, tests, or ad hoc startup.
  """

  alias Jido.Browser.Adapters.AgentBrowser
  alias Jido.Browser.Error

  @default_name :default

  @typedoc "Options forwarded to the underlying AgentBrowser warm pool."
  @type option ::
          {:name, atom() | {:global, term()} | {:via, module(), term()}}
          | {:size, pos_integer()}
          | {:adapter, module()}
          | {:headless, boolean()}
          | {:headed, boolean()}
          | {:timeout, pos_integer()}
          | {:checkout_timeout, pos_integer()}
          | {:startup_timeout, pos_integer()}
          | {:pool_runtime_module, module()}
          | {atom(), term()}

  @doc """
  Returns a supervisor child specification for a named warm pool.

  `name` defaults to `:default`. For supervised pools, `name` must be a valid
  process name such as an atom, `{:global, term}`, or `{:via, module, term}`.
  """
  @spec child_spec([option()]) :: Supervisor.child_spec()
  def child_spec(opts) do
    opts = Keyword.put_new(opts, :name, @default_name)
    name = Keyword.fetch!(opts, :name)

    %{
      id: {__MODULE__, name},
      start: {__MODULE__, :start_link, [opts]},
      type: :worker
    }
  end

  @doc """
  Starts a warm pool under the calling supervisor.

  This is primarily used by OTP supervisors through the child spec. Most
  consumers should add `{Jido.Browser.Pool, ...}` to their supervision tree
  instead of calling `start_link/1` directly.
  """
  @spec start_link([option()]) :: GenServer.on_start()
  def start_link(opts) do
    opts = Keyword.put_new(opts, :name, @default_name)
    adapter = Keyword.get(opts, :adapter, AgentBrowser)

    cond do
      not valid_process_name?(opts[:name]) ->
        {:error,
         Error.invalid_error(
           "Supervised pool name must be an atom, {:global, term}, or {:via, module, term}",
           %{name: opts[:name]}
         )}

      adapter == AgentBrowser and function_exported?(adapter, :start_supervised_pool, 1) ->
        adapter.start_supervised_pool(opts)

      true ->
        {:error,
         Error.invalid_error(
           "Adapter #{inspect(adapter)} does not support supervised warm pools",
           %{adapter: adapter}
         )}
    end
  end

  defp valid_process_name?(name) when is_atom(name), do: true
  defp valid_process_name?({:global, _term}), do: true
  defp valid_process_name?({:via, _module, _term}), do: true
  defp valid_process_name?(_name), do: false
end
