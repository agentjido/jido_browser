defmodule Jido.Browser.Actions.Reload do
  @moduledoc """
  Jido Action for reloading the current page.

  ## Usage with Jido Agent

      # In your agent's tool list
      tools: [Jido.Browser.Actions.Reload]

      # The agent can then call:
      # reload()

  """

  use Jido.Action,
    name: "browser_reload",
    description: "Reload the current page",
    category: "Browser",
    tags: ["browser", "navigation", "web"],
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

      case Jido.Browser.reload(session, opts) do
        {:ok, updated_session, result} ->
          {:ok, %{status: "success", action: "reload", result: result, session: updated_session}}

        {:error, %Error.EvaluationError{} = error} ->
          {:error, error}

        {:error, reason} ->
          {:error, Error.navigation_error("reload", reason)}
      end
    end
  end
end
