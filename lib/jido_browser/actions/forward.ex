defmodule JidoBrowser.Actions.Forward do
  @moduledoc """
  Jido Action for navigating forward in browser history.

  ## Usage with Jido Agent

      # In your agent's tool list
      tools: [JidoBrowser.Actions.Forward]

      # The agent can then call:
      # forward()

  """

  use Jido.Action,
    name: "browser_forward",
    description: "Navigate forward in browser history",
    category: "Browser",
    tags: ["browser", "navigation", "history", "web"],
    vsn: "1.0.0",
    schema: [
      timeout: [type: :integer, doc: "Timeout in milliseconds"]
    ]

  alias JidoBrowser.ActionHelpers
  alias JidoBrowser.Error

  @impl true
  def run(params, context) do
    with {:ok, session} <- ActionHelpers.get_session(context) do
      opts = if params[:timeout], do: [timeout: params[:timeout]], else: []

      case JidoBrowser.evaluate(session, "window.history.forward()", opts) do
        {:ok, updated_session, _} ->
          {:ok, %{status: "success", action: "forward", session: updated_session}}

        {:error, %Error.EvaluationError{} = error} ->
          {:error, error}

        {:error, reason} ->
          {:error, Error.navigation_error("history:forward", reason)}
      end
    end
  end
end
