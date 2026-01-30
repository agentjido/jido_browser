defmodule JidoBrowser.Actions.Click do
  @moduledoc """
  Jido Action for clicking an element.

  ## Usage with Jido Agent

      # In your agent's tool list
      tools: [JidoBrowser.Actions.Click]

      # The agent can then call:
      # click(selector: "button#submit")
      # click(selector: "a.nav-link", text: "About")

  """

  use Jido.Action,
    name: "browser_click",
    description: "Click an element in the browser",
    category: "Browser",
    tags: ["browser", "interaction", "web"],
    vsn: "1.0.0",
    schema: [
      selector: [type: :string, required: true, doc: "CSS selector for the element to click"],
      text: [type: :string, doc: "Optional text content to match within the selector"],
      timeout: [type: :integer, doc: "Timeout in milliseconds"]
    ]

  alias JidoBrowser.ActionHelpers
  alias JidoBrowser.Error

  @impl true
  def run(params, context) do
    with {:ok, session} <- ActionHelpers.get_session(context) do
      opts = Keyword.new(params) |> Keyword.take([:text, :timeout])

      case JidoBrowser.click(session, params.selector, opts) do
        {:ok, updated_session, result} ->
          {:ok, %{status: "success", selector: params.selector, result: result, session: updated_session}}

        {:error, %Error.ElementError{} = error} ->
          {:error, error}

        {:error, reason} ->
          {:error, Error.element_error("click", params.selector, reason)}
      end
    end
  end
end
