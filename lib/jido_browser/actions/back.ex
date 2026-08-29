defmodule Jido.Browser.Actions.Back do
  @moduledoc """
  Jido Action for navigating back in browser history.

  ## Usage with Jido Agent

      # In your agent's tool list
      tools: [Jido.Browser.Actions.Back]

      # The agent can then call:
      # back()

  """

  use Jido.Browser.Action,
    name: "browser_back",
    description: "Navigate back in browser history",
    schema: Zoi.object(%{timeout: Zoi.integer(description: "Timeout in milliseconds") |> Zoi.optional()}),
    output_schema:
      Zoi.object(%{
        status: Zoi.literal("success"),
        action: Zoi.literal("back"),
        result: Zoi.map(),
        session: Zoi.any()
      })

  alias Jido.Browser.ActionHelpers
  alias Jido.Browser.Error

  @impl true
  def run(params, context) do
    with {:ok, session} <- ActionHelpers.get_session(context) do
      opts = if params[:timeout], do: [timeout: params[:timeout]], else: []

      case Jido.Browser.back(session, opts) do
        {:ok, updated_session, result} ->
          {:ok, %{status: "success", action: "back", result: result, session: updated_session}}

        {:error, %Error.EvaluationError{} = error} ->
          {:error, error}

        {:error, reason} ->
          {:error, Error.navigation_error("history:back", reason)}
      end
    end
  end
end
