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

  use Jido.Action,
    name: "browser_evaluate",
    description: "Execute JavaScript in the browser and return the result",
    category: "Browser",
    tags: ["browser", "javascript", "evaluate", "web"],
    vsn: "2.0.0",
    schema: [
      script: [type: :string, required: true, doc: "JavaScript code to execute"],
      timeout: [type: :integer, doc: "Timeout in milliseconds"]
    ]

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
