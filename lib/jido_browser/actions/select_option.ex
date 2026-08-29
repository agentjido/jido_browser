defmodule Jido.Browser.Actions.SelectOption do
  @moduledoc """
  Jido Action for selecting an option from a dropdown.

  ## Usage with Jido Agent

      # In your agent's tool list
      tools: [Jido.Browser.Actions.SelectOption]

      # The agent can then call:
      # select_option(selector: "select#country", value: "US")
      # select_option(selector: "select#country", label: "United States")
      # select_option(selector: "select#country", index: 0)

  """

  use Jido.Browser.Action,
    name: "browser_select_option",
    description: "Select an option from a dropdown element",
    schema:
      Zoi.object(%{
        selector: Zoi.string(description: "CSS selector for the select element"),
        value: Zoi.string(description: "Option value to select") |> Zoi.optional(),
        label: Zoi.string(description: "Option label/text to select") |> Zoi.optional(),
        index: Zoi.integer(description: "Option index to select (0-based)") |> Zoi.optional()
      }),
    output_schema:
      Zoi.object(%{
        status: Zoi.literal("success"),
        selector: Zoi.string(),
        result: Zoi.map(),
        session: Zoi.any()
      })

  alias Jido.Browser.ActionHelpers
  alias Jido.Browser.Error

  @impl true
  def run(params, context) do
    with {:ok, session} <- ActionHelpers.get_session(context) do
      selector = params.selector
      opts = select_opts(params)

      case Jido.Browser.select_option(session, selector, opts) do
        {:ok, updated_session, data} ->
          handle_select_result(selector, updated_session, data)

        {:error, reason} ->
          {:error, Error.element_error("select_option", selector, reason)}
      end
    end
  end

  defp handle_select_result(selector, updated_session, data) do
    result = ActionHelpers.unwrap_result(data)

    if ActionHelpers.get_value(result, :selected) == false do
      {:error,
       Error.element_error(
         "select_option",
         selector,
         ActionHelpers.get_value(result, :error) || "Selection failed"
       )}
    else
      {:ok, %{status: "success", selector: selector, result: result, session: updated_session}}
    end
  end

  defp select_opts(params) do
    params
    |> Keyword.new()
    |> Keyword.take([:value, :label, :index, :timeout])
  end
end
