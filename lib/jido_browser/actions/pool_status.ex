defmodule Jido.Browser.Actions.PoolStatus do
  @moduledoc """
  Jido Action for inspecting a warm browser pool.
  """

  use Jido.Browser.Action,
    name: "browser_pool_status",
    description: "Return readiness and lifecycle status for a warm browser pool.",
    schema:
      Zoi.object(%{
        pool:
          Zoi.any(description: "Warm pool name or pid. Defaults to plugin pool state.")
          |> Zoi.optional()
      }),
    output_schema:
      Zoi.object(%{
        status: Zoi.literal("success"),
        pool: Zoi.any(),
        pool_status: Zoi.map()
      })

  alias Jido.Browser.Error

  @impl true
  def run(params, context) do
    with {:ok, pool} <- pool_name(params, context),
         {:ok, status} <- Jido.Browser.pool_status(pool) do
      {:ok, %{status: "success", pool: pool, pool_status: status}}
    else
      {:error, error} -> {:error, error}
    end
  end

  defp pool_name(params, context) do
    case Map.get(params, :pool) || get_in(context, [:skill_state, :pool]) do
      nil -> {:error, Error.invalid_error("Pool name is required", %{})}
      pool -> {:ok, pool}
    end
  end
end
