defmodule JidoBrowser.Actions.Focus do
  @moduledoc """
  Jido Action for focusing on an element.

  ## Usage with Jido Agent

      # In your agent's tool list
      tools: [JidoBrowser.Actions.Focus]

      # The agent can then call:
      # focus(selector: "input#email")
      # focus(selector: "textarea.comment", timeout: 5000)

  """

  use Jido.Action,
    name: "browser_focus",
    description: "Focus on an element in the browser",
    category: "Browser",
    tags: ["browser", "interaction", "focus", "web"],
    vsn: "1.0.0",
    schema: [
      selector: [type: :string, required: true, doc: "CSS selector for the element to focus"],
      timeout: [type: :integer, doc: "Timeout in milliseconds"]
    ]

  alias JidoBrowser.ActionHelpers
  alias JidoBrowser.Error

  @impl true
  def run(params, context) do
    with {:ok, session} <- ActionHelpers.get_session(context) do
      selector = params.selector

      script = """
      (() => {
        const el = document.querySelector(#{inspect(selector)});
        if (el) {
          el.focus();
          return {focused: true, selector: #{inspect(selector)}, activeElement: document.activeElement === el};
        }
        return {focused: false, error: 'Element not found'};
      })()
      """

      opts = Keyword.new(params) |> Keyword.take([:timeout])

      case JidoBrowser.evaluate(session, script, opts) do
        {:ok, updated_session, %{result: %{"focused" => true} = result}} ->
          {:ok, %{status: "success", selector: selector, result: result, session: updated_session}}

        {:ok, _updated_session, %{result: %{"focused" => false, "error" => error}}} ->
          {:error, Error.element_error("focus", selector, error)}

        {:error, reason} ->
          {:error, Error.element_error("focus", selector, reason)}
      end
    end
  end
end
