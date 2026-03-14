defmodule Jido.Browser.Actions.Forward do
  @moduledoc """
  Jido Action for navigating forward in browser history.

  ## Usage with Jido Agent

      # In your agent's tool list
      tools: [Jido.Browser.Actions.Forward]

      # The agent can then call:
      # forward()

  """

  use Jido.Action,
    name: "browser_forward",
    description: "Navigate forward in browser history",
    category: "Browser",
    tags: ["browser", "navigation", "history", "web"],
    vsn: "2.0.0",
    schema: [
      timeout: [type: :integer, doc: "Timeout in milliseconds"]
    ]

  alias Jido.Browser.ActionHelpers
  alias Jido.Browser.Error

  @impl true
  def run(params, context) do
    with {:ok, session} <- ActionHelpers.get_session(context) do
      opts = if params[:timeout], do: [timeout: params[:timeout]], else: []

      case Jido.Browser.forward(session, opts) do
        {:ok, updated_session, result} ->
          {:ok, %{status: "success", action: "forward", result: result, session: updated_session}}

        {:error, %Error.EvaluationError{} = error} ->
          {:error, error}

        {:error, reason} ->
          {:error, Error.navigation_error("history:forward", reason)}
      end
    end
  end
end
