defmodule JidoBrowser.Actions.Query do
  @moduledoc """
  Jido Action for querying elements matching a selector.

  ## Usage with Jido Agent

      # In your agent's tool list
      tools: [JidoBrowser.Actions.Query]

      # The agent can then call:
      # query(selector: "div.item")
      # query(selector: "button", limit: 5)

  """

  use Jido.Action,
    name: "browser_query",
    description: "Query for elements matching a CSS selector",
    category: "Browser",
    tags: ["browser", "query", "web"],
    vsn: "1.0.0",
    schema: [
      selector: [type: :string, required: true, doc: "CSS selector to query"],
      limit: [type: :integer, default: 10, doc: "Maximum number of elements to return"]
    ]

  alias JidoBrowser.ActionHelpers
  alias JidoBrowser.Error

  @impl true
  def run(params, context) do
    with {:ok, session} <- ActionHelpers.get_session(context) do
      selector = params.selector
      limit = Map.get(params, :limit, 10)

      script = """
      (function() {
        const selector = #{Jason.encode!(selector)};
        const limit = #{limit};
        return Array.from(document.querySelectorAll(selector)).slice(0, limit).map((el, i) => ({
          index: i,
          tag: el.tagName.toLowerCase(),
          id: el.id || null,
          classes: Array.from(el.classList),
          text: el.innerText?.substring(0, 100) || ''
        }));
      })()
      """

      case JidoBrowser.evaluate(session, script, []) do
        {:ok, updated_session, %{result: elements}} when is_list(elements) ->
          {:ok, %{status: "success", count: length(elements), elements: elements, session: updated_session}}

        {:ok, updated_session, %{result: _}} ->
          {:ok, %{status: "success", count: 0, elements: [], session: updated_session}}

        {:error, reason} ->
          {:error, Error.element_error("query", selector, reason)}
      end
    end
  end
end
