defmodule Jido.Browser.Actions.Evaluate do
  @moduledoc """
  Jido Action for executing JavaScript in the browser.

  ## Usage with Jido Agent

      # In your agent's tool list
      tools: [Jido.Browser.Actions.Evaluate]

      # The agent can then call:
      # evaluate(script: "document.title")
      # evaluate(script: "document.querySelectorAll('a').length")

  """

  use Jido.Browser.Action,
    name: "browser_evaluate",
    description: "Execute JavaScript in the browser and return the result",
    schema:
      Zoi.object(%{
        script: Zoi.string(description: "JavaScript code to execute"),
        timeout: Zoi.integer(description: "Timeout in milliseconds") |> Zoi.optional()
      })

  alias Jido.Browser.ActionHelpers
  alias Jido.Browser.Error

  @impl true
  def run(params, context) do
    with {:ok, session} <- ActionHelpers.get_session(context) do
      opts = Keyword.new(params) |> Keyword.take([:timeout])

      case Jido.Browser.evaluate(session, params.script, opts) do
        {:ok, updated_session, %{result: result}} ->
          {:ok, %{status: "success", result: result, session: updated_session}}

        {:error, reason} ->
          {:error, Error.adapter_error("Evaluate failed", %{reason: reason})}
      end
    end
  end
end
