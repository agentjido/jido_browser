defmodule Jido.Browser.Actions.IsVisible do
  @moduledoc """
  Jido Action for checking if an element is visible.

  ## Usage with Jido Agent

      # In your agent's tool list
      tools: [Jido.Browser.Actions.IsVisible]

      # The agent can then call:
      # is_visible(selector: "#modal")
      # is_visible(selector: ".loading-spinner")

  """

  use Jido.Action,
    name: "browser_is_visible",
    description: "Check if an element is visible",
    category: "Browser",
    tags: ["browser", "query", "web"],
    vsn: "2.0.0",
    schema: [
      selector: [type: :string, required: true, doc: "CSS selector for the element"]
    ]

  alias Jido.Browser.ActionHelpers
  alias Jido.Browser.Error

  @impl true
  def run(params, context) do
    with {:ok, session} <- ActionHelpers.get_session(context) do
      selector = params.selector

      case Jido.Browser.is_visible(session, selector) do
        {:ok, updated_session, data} ->
          result = ActionHelpers.unwrap_result(data)

          {:ok,
           %{
             exists: ActionHelpers.get_value(result, :exists),
             visible: ActionHelpers.get_value(result, :visible),
             session: updated_session
           }}

        {:error, reason} ->
          {:error, Error.element_error("is_visible", selector, reason)}
      end
    end
  end
end
