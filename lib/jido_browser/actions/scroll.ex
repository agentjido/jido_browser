defmodule Jido.Browser.Actions.Scroll do
  @moduledoc """
  Jido Action for scrolling the page.

  ## Usage with Jido Agent

      # In your agent's tool list
      tools: [Jido.Browser.Actions.Scroll]

      # The agent can then call:
      # scroll(direction: :down)
      # scroll(direction: :top)
      # scroll(x: 0, y: 500)
      # scroll(selector: "#target-element")

  """

  use Jido.Browser.Action,
    name: "browser_scroll",
    description: "Scroll the page by pixels, to preset positions, or to an element",
    schema:
      Zoi.object(%{
        x: Zoi.integer(description: "Horizontal scroll pixels") |> Zoi.optional(),
        y: Zoi.integer(description: "Vertical scroll pixels") |> Zoi.optional(),
        direction:
          Zoi.enum([:up, :down, :top, :bottom], description: "Preset scroll direction")
          |> Zoi.optional(),
        selector: Zoi.string(description: "CSS selector to scroll element into view") |> Zoi.optional()
      }),
    output_schema:
      Zoi.object(%{
        status: Zoi.literal("success"),
        result: Zoi.map(),
        session: Zoi.any()
      })

  alias Jido.Browser.ActionHelpers
  alias Jido.Browser.Error

  @impl true
  def run(params, context) do
    with {:ok, session} <- ActionHelpers.get_session(context) do
      case Jido.Browser.scroll(session, Keyword.new(params)) do
        {:ok, updated_session, data} ->
          handle_scroll_result(params, updated_session, data)

        {:error, reason} ->
          {:error, Error.adapter_error("Scroll failed", %{reason: reason})}
      end
    end
  end

  defp handle_scroll_result(params, updated_session, data) do
    result = ActionHelpers.unwrap_result(data)

    if ActionHelpers.get_value(result, :scrolled) == false do
      handle_scroll_error(params, result)
    else
      {:ok, %{status: "success", result: result, session: updated_session}}
    end
  end

  defp handle_scroll_error(%{selector: selector}, result) do
    {:error,
     Error.element_error(
       "scroll",
       selector,
       ActionHelpers.get_value(result, :error) || "Element not found"
     )}
  end

  defp handle_scroll_error(_params, result) do
    {:error,
     Error.adapter_error("Scroll failed", %{
       reason: ActionHelpers.get_value(result, :error) || "Scroll command failed"
     })}
  end
end
