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

  use Jido.Action,
    name: "browser_query",
    description: "Query for elements matching a CSS selector",
    category: "Browser",
    tags: ["browser", "query", "web"],
    vsn: "2.0.0",
    schema: [
      selector: [type: :string, required: true, doc: "CSS selector to query"],
      limit: [type: :integer, default: 10, doc: "Maximum number of elements to return"]
    ]

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
