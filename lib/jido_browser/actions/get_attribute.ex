defmodule Jido.Browser.Actions.GetAttribute do
  @moduledoc """
  Jido Action for getting an attribute value from an element.

  ## Usage with Jido Agent

      # In your agent's tool list
      tools: [Jido.Browser.Actions.GetAttribute]

      # The agent can then call:
      # get_attribute(selector: "a.link", attribute: "href")
      # get_attribute(selector: "img", attribute: "src")

  """

  use Jido.Action,
    name: "browser_get_attribute",
    description: "Get an attribute value from an element",
    category: "Browser",
    tags: ["browser", "query", "web"],
    vsn: "2.0.0",
    schema: [
      selector: [type: :string, required: true, doc: "CSS selector for the element"],
      attribute: [type: :string, required: true, doc: "Attribute name to get"]
    ]

  alias Jido.Browser.ActionHelpers
  alias Jido.Browser.Error

  @impl true
  def run(params, context) do
    with {:ok, session} <- ActionHelpers.get_session(context) do
      selector = params.selector
      attribute = params.attribute

      case Jido.Browser.get_attribute(session, selector, attribute) do
        {:ok, updated_session, result} ->
          handle_attribute_result(selector, attribute, updated_session, result)

        {:error, reason} ->
          {:error, Error.element_error("get_attribute", selector, reason)}
      end
    end
  end

  defp handle_attribute_result(selector, attribute, updated_session, result) do
    case ActionHelpers.get_value(result, :value) do
      nil ->
        {:error, Error.element_error("get_attribute", selector, "Element not found or attribute missing")}

      value ->
        {:ok,
         %{
           status: "success",
           selector: selector,
           attribute: attribute,
           value: value,
           session: updated_session
         }}
    end
  end
end
