defmodule JidoBrowser.Actions.Reload do
  @moduledoc """
  Jido Action for reloading the current page.

  ## Usage with Jido Agent

      # In your agent's tool list
      tools: [JidoBrowser.Actions.Reload]

      # The agent can then call:
      # reload()

  """

  use Jido.Action,
    name: "browser_reload",
    description: "Reload the current page",
    category: "Browser",
    tags: ["browser", "navigation", "web"],
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

      case JidoBrowser.evaluate(session, "window.location.reload()", opts) do
        {:ok, updated_session, _} ->
          {:ok, %{status: "success", action: "reload", session: updated_session}}

        {:error, %Error.EvaluationError{} = error} ->
          {:error, error}

        {:error, reason} ->
          {:error, Error.navigation_error("reload", reason)}
      end
    end
  end
end
