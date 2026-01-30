defmodule JidoBrowser.Actions.Type do
  @moduledoc """
  Jido Action for typing text into an element.

  ## Usage with Jido Agent

      # In your agent's tool list
      tools: [JidoBrowser.Actions.Type]

      # The agent can then call:
      # type(selector: "input#email", text: "user@example.com")

  """

  use Jido.Action,
    name: "browser_type",
    description: "Type text into an element in the browser",
    category: "Browser",
    tags: ["browser", "interaction", "input", "web"],
    vsn: "1.0.0",
    schema: [
      selector: [type: :string, required: true, doc: "CSS selector for the input element"],
      text: [type: :string, required: true, doc: "Text to type into the element"],
      clear: [type: :boolean, default: false, doc: "Clear the field before typing"],
      timeout: [type: :integer, doc: "Timeout in milliseconds"]
    ]

  alias JidoBrowser.Error

  @impl true
  def run(params, context) do
    session = get_session(context)
    opts = Keyword.new(params) |> Keyword.take([:clear, :timeout])

    case JidoBrowser.type(session, params.selector, params.text, opts) do
      {:ok, result} ->
        {:ok, %{status: "success", selector: params.selector, result: result}}

      {:error, %Error.ElementError{} = error} ->
        {:error, error}

      {:error, reason} ->
        {:error, Error.element_error("type", params.selector, reason)}
    end
  end

  defp get_session(context) do
    context[:session] ||
      context[:browser_session] ||
      get_in(context, [:tool_context, :session]) ||
      raise "No browser session in context"
  end
end
