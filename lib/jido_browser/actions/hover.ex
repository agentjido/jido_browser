defmodule Jido.Browser.Actions.Hover do
  @moduledoc """
  Jido Action for hovering over an element.

  ## Usage with Jido Agent

      # In your agent's tool list
      tools: [Jido.Browser.Actions.Hover]

      # The agent can then call:
      # hover(selector: "button.menu")
      # hover(selector: ".dropdown-trigger", timeout: 5000)

  """

  use Jido.Action,
    name: "browser_hover",
    description: "Hover over an element in the browser",
    category: "Browser",
    tags: ["browser", "interaction", "hover", "web"],
    vsn: "2.0.0",
    schema: [
      selector: [type: :string, required: true, doc: "CSS selector for the element to hover"],
      timeout: [type: :integer, doc: "Timeout in milliseconds"]
    ]

  alias Jido.Browser.ActionHelpers
  alias Jido.Browser.Error

  @impl true
  def run(params, context) do
    with {:ok, session} <- ActionHelpers.get_session(context) do
      selector = params.selector
      opts = Keyword.new(params) |> Keyword.take([:timeout])

      case Jido.Browser.hover(session, selector, opts) do
        {:ok, updated_session, data} ->
          handle_hover_result(selector, updated_session, data)

        {:error, reason} ->
          {:error, Error.element_error("hover", selector, reason)}
      end
    end
  end

  defp handle_hover_result(selector, updated_session, data) do
    result = ActionHelpers.unwrap_result(data)

    if ActionHelpers.get_value(result, :hovered) == false do
      {:error,
       Error.element_error(
         "hover",
         selector,
         ActionHelpers.get_value(result, :error) || "Element not found"
       )}
    else
      {:ok, %{status: "success", selector: selector, result: result, session: updated_session}}
    end
  end
end
