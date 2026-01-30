defmodule JidoBrowser.Actions.Hover do
  @moduledoc """
  Jido Action for hovering over an element.

  ## Usage with Jido Agent

      # In your agent's tool list
      tools: [JidoBrowser.Actions.Hover]

      # The agent can then call:
      # hover(selector: "button.menu")
      # hover(selector: ".dropdown-trigger", timeout: 5000)

  """

  use Jido.Action,
    name: "browser_hover",
    description: "Hover over an element in the browser",
    category: "Browser",
    tags: ["browser", "interaction", "hover", "web"],
    vsn: "1.0.0",
    schema: [
      selector: [type: :string, required: true, doc: "CSS selector for the element to hover"],
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
          el.dispatchEvent(new MouseEvent('mouseenter', {bubbles: true, cancelable: true}));
          el.dispatchEvent(new MouseEvent('mouseover', {bubbles: true, cancelable: true}));
          return {hovered: true, selector: #{inspect(selector)}};
        }
        return {hovered: false, error: 'Element not found'};
      })()
      """

      opts = Keyword.new(params) |> Keyword.take([:timeout])

      case JidoBrowser.evaluate(session, script, opts) do
        {:ok, updated_session, %{result: %{"hovered" => true} = result}} ->
          {:ok, %{status: "success", selector: selector, result: result, session: updated_session}}

        {:ok, _updated_session, %{result: %{"hovered" => false, "error" => error}}} ->
          {:error, Error.element_error("hover", selector, error)}

        {:error, reason} ->
          {:error, Error.element_error("hover", selector, reason)}
      end
    end
  end
end
