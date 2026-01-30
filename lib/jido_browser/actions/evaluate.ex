defmodule JidoBrowser.Actions.Evaluate do
  @moduledoc """
  Jido Action for executing JavaScript in the browser.

  ## Usage with Jido Agent

      # In your agent's tool list
      tools: [JidoBrowser.Actions.Evaluate]

      # The agent can then call:
      # evaluate(script: "document.title")
      # evaluate(script: "document.querySelectorAll('a').length")

  """

  use Jido.Action,
    name: "browser_evaluate",
    description: "Execute JavaScript in the browser and return the result",
    category: "Browser",
    tags: ["browser", "javascript", "evaluate", "web"],
    vsn: "1.0.0",
    schema: [
      script: [type: :string, required: true, doc: "JavaScript code to execute"],
      timeout: [type: :integer, doc: "Timeout in milliseconds"]
    ]

  alias JidoBrowser.Error

  @impl true
  def run(params, context) do
    session = get_session(context)
    opts = Keyword.new(params) |> Keyword.take([:timeout])

    case JidoBrowser.evaluate(session, params.script, opts) do
      {:ok, %{result: result}} ->
        {:ok, %{status: "success", result: result}}

      {:error, reason} ->
        {:error, Error.adapter_error("Evaluate failed", %{reason: reason})}
    end
  end

  defp get_session(context) do
    context[:session] ||
      context[:browser_session] ||
      get_in(context, [:tool_context, :session]) ||
      raise "No browser session in context"
  end
end
