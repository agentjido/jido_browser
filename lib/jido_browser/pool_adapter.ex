defmodule Jido.Browser.PoolAdapter do
  @moduledoc """
  Optional behaviour for adapters that support warm pooled sessions.

  Pool-capable adapters keep the public `Jido.Browser` API flat by exposing the
  same pool lifecycle functions behind a common capability boundary.
  """

  @callback start_pool(keyword()) :: {:ok, pid()} | {:error, term()}
  @callback start_supervised_pool(keyword()) :: GenServer.on_start()
  @callback stop_pool(term()) :: :ok | {:error, term()}

  @doc false
  @spec supports_pools?(module()) :: boolean()
  def supports_pools?(adapter) when is_atom(adapter) do
    Code.ensure_loaded?(adapter) and
      function_exported?(adapter, :start_pool, 1) and
      function_exported?(adapter, :start_supervised_pool, 1) and
      function_exported?(adapter, :stop_pool, 1)
  end

  def supports_pools?(_adapter), do: false
end
