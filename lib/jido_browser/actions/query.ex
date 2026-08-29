defmodule Jido.Browser.Actions.Query do
  @moduledoc """
  Jido Action for querying elements matching a selector.

  ## Usage with Jido Agent

      # In your agent's tool list
      tools: [Jido.Browser.Actions.Query]

      # The agent can then call:
      # query(selector: "div.item")
      # query(selector: "button", limit: 5)

  """

  use Jido.Browser.Action,
    name: "browser_query",
    description: "Query for elements matching a CSS selector",
    schema:
      Zoi.object(%{
        selector: Zoi.string(description: "CSS selector to query"),
        limit:
          Zoi.integer(description: "Maximum number of elements to return")
          |> Zoi.default(10)
          |> Zoi.optional()
      }),
    output_schema:
      Zoi.object(%{
        status: Zoi.literal("success"),
        count: Zoi.integer(gte: 0),
        elements: Zoi.list(Zoi.map()),
        session: Zoi.any()
      })

  alias Jido.Browser.ActionHelpers
  alias Jido.Browser.Error

  @impl true
  def run(params, context) do
    with {:ok, session} <- ActionHelpers.get_session(context) do
      selector = params.selector
      limit = Map.get(params, :limit, 10)

      case Jido.Browser.query(session, selector, limit: limit) do
        {:ok, updated_session, data} ->
          result = ActionHelpers.unwrap_result(data)
          {:ok, result |> Map.put(:status, "success") |> Map.put(:session, updated_session)}

        {:error, reason} ->
          {:error, Error.element_error("query", selector, reason)}
      end
    end
  end
end
