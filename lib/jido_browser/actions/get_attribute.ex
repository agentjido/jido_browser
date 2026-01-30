defmodule JidoBrowser.Actions.GetAttribute do
  @moduledoc """
  Jido Action for getting an attribute value from an element.

  ## Usage with Jido Agent

      # In your agent's tool list
      tools: [JidoBrowser.Actions.GetAttribute]

      # The agent can then call:
      # get_attribute(selector: "a.link", attribute: "href")
      # get_attribute(selector: "img", attribute: "src")

  """

  use Jido.Action,
    name: "browser_get_attribute",
    description: "Get an attribute value from an element",
    category: "Browser",
    tags: ["browser", "query", "web"],
    vsn: "1.0.0",
    schema: [
      selector: [type: :string, required: true, doc: "CSS selector for the element"],
      attribute: [type: :string, required: true, doc: "Attribute name to get"]
    ]

  alias JidoBrowser.ActionHelpers
  alias JidoBrowser.Error

  @impl true
  def run(params, context) do
    with {:ok, session} <- ActionHelpers.get_session(context) do
      selector = params.selector
      attribute = params.attribute

      script = """
      (function() {
        const selector = #{Jason.encode!(selector)};
        const attribute = #{Jason.encode!(attribute)};
        const el = document.querySelector(selector);
        return el ? el.getAttribute(attribute) : null;
      })()
      """

      case JidoBrowser.evaluate(session, script, []) do
        {:ok, _updated_session, %{result: nil}} ->
          {:error, Error.element_error("get_attribute", selector, "Element not found or attribute missing")}

        {:ok, updated_session, %{result: value}} ->
          {:ok,
           %{
             status: "success",
             selector: selector,
             attribute: attribute,
             value: value,
             session: updated_session
           }}

        {:error, reason} ->
          {:error, Error.element_error("get_attribute", selector, reason)}
      end
    end
  end
end
