defmodule Jido.Browser.Actions.GetText do
  @moduledoc """
  Jido Action for getting text content of an element.

  ## Usage with Jido Agent

      # In your agent's tool list
      tools: [Jido.Browser.Actions.GetText]

      # The agent can then call:
      # get_text(selector: "h1")
      # get_text(selector: "p.description", all: true)

  """

  use Jido.Browser.Action,
    name: "browser_get_text",
    description: "Get text content of an element",
    schema:
      Zoi.object(%{
        selector: Zoi.string(description: "CSS selector for the element"),
        all:
          Zoi.boolean(description: "Get text from all matching elements")
          |> Zoi.default(false)
          |> Zoi.optional()
      }),
    output_schema:
      Zoi.object(%{
        status: Zoi.literal("success"),
        selector: Zoi.string(),
        text: Zoi.string() |> Zoi.optional(),
        texts: Zoi.list(Zoi.string()) |> Zoi.optional(),
        session: Zoi.any()
      })

  alias Jido.Browser.ActionHelpers
  alias Jido.Browser.Error

  @impl true
  def run(params, context) do
    with {:ok, session} <- ActionHelpers.get_session(context) do
      selector = params.selector
      all = Map.get(params, :all, false)

      case Jido.Browser.get_text(session, selector, all: all) do
        {:ok, updated_session, result} ->
          handle_text_result(selector, updated_session, result)

        {:error, reason} ->
          {:error, Error.element_error("get_text", selector, reason)}
      end
    end
  end

  defp handle_text_result(selector, updated_session, result) do
    case ActionHelpers.get_value(result, :texts) do
      texts when is_list(texts) ->
        {:ok, %{status: "success", selector: selector, texts: texts, session: updated_session}}

      _ ->
        single_text_result(selector, updated_session, result)
    end
  end

  defp single_text_result(selector, updated_session, result) do
    case ActionHelpers.get_value(result, :text) do
      nil ->
        {:error, Error.element_error("get_text", selector, "Element not found")}

      text ->
        {:ok, %{status: "success", selector: selector, text: text, session: updated_session}}
    end
  end
end
