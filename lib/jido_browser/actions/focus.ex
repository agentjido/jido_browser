defmodule Jido.Browser.Actions.Focus do
  @moduledoc """
  Jido Action for focusing on an element.

  ## Usage with Jido Agent

      # In your agent's tool list
      tools: [Jido.Browser.Actions.Focus]

      # The agent can then call:
      # focus(selector: "input#email")
      # focus(selector: "textarea.comment", timeout: 5000)

  """

  use Jido.Browser.Action,
    name: "browser_focus",
    description: "Focus on an element in the browser",
    schema:
      Zoi.object(%{
        selector: Zoi.string(description: "CSS selector for the element to focus"),
        timeout: Zoi.integer(description: "Timeout in milliseconds") |> Zoi.optional()
      })

  alias Jido.Browser.ActionHelpers
  alias Jido.Browser.Error

  @impl true
  def run(params, context) do
    with {:ok, session} <- ActionHelpers.get_session(context) do
      selector = params.selector
      opts = Keyword.new(params) |> Keyword.take([:timeout])

      case Jido.Browser.focus(session, selector, opts) do
        {:ok, updated_session, data} ->
          handle_focus_result(selector, updated_session, data)

        {:error, reason} ->
          {:error, Error.element_error("focus", selector, reason)}
      end
    end
  end

  defp handle_focus_result(selector, updated_session, data) do
    result = ActionHelpers.unwrap_result(data)

    if ActionHelpers.get_value(result, :focused) == false do
      {:error,
       Error.element_error(
         "focus",
         selector,
         ActionHelpers.get_value(result, :error) || "Element not found"
       )}
    else
      {:ok, %{status: "success", selector: selector, result: result, session: updated_session}}
    end
  end
end
