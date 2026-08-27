defmodule Jido.Browser.WarmPool.Runtime do
  @moduledoc false

  @type pool_state :: %{
          required(:worker_opts) => keyword(),
          optional(atom()) => term()
        }

  @callback start_worker(pool_state()) :: {:ok, map()} | {:error, term()}
  @callback command(map(), map(), pos_integer()) :: {:ok, map()} | {:error, term()}
  @callback shutdown_worker(map()) :: :ok | {:error, term()}
  @callback health_check(map()) :: :ok | {:error, term()}

  @optional_callbacks health_check: 1

  @doc false
  @spec context(pool_state()) :: term()
  def context(pool_state), do: Map.get(pool_state, :runtime_context)

  @doc false
  @spec healthy?(module(), map()) :: :ok | {:error, term()}
  def healthy?(runtime_module, worker_state) do
    if function_exported?(runtime_module, :health_check, 1) do
      runtime_module.health_check(worker_state)
    else
      :ok
    end
  end
end
