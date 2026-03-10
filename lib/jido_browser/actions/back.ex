defmodule Jido.Browser.Actions.Back do
  @moduledoc """
  Jido Action for navigating back in browser history.

  ## Usage with Jido Agent

      # In your agent's tool list
      tools: [Jido.Browser.Actions.Back]

      # The agent can then call:
      # back()

  """

  use Jido.Action,
    name: "browser_back",
    description: "Navigate back in browser history",
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

      case Jido.Browser.evaluate(session, "window.history.back()", opts) do
        {:ok, updated_session, _} ->
          {:ok, %{status: "success", action: "back", session: updated_session}}

        {:error, %Error.EvaluationError{} = error} ->
          {:error, error}

        {:error, reason} ->
          {:error, Error.navigation_error("history:back", reason)}
      end
    end
  end
end
