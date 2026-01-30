defmodule JidoBrowser.Actions.GetText do
  @moduledoc """
  Jido Action for getting text content of an element.

  ## Usage with Jido Agent

      # In your agent's tool list
      tools: [JidoBrowser.Actions.GetText]

      # The agent can then call:
      # get_text(selector: "h1")
      # get_text(selector: "p.description", all: true)

  """

  use Jido.Action,
    name: "browser_get_text",
    description: "Get text content of an element",
    category: "Browser",
    tags: ["browser", "query", "web"],
    vsn: "1.0.0",
    schema: [
      selector: [type: :string, required: true, doc: "CSS selector for the element"],
      all: [type: :boolean, default: false, doc: "Get text from all matching elements"]
    ]

  alias JidoBrowser.ActionHelpers
  alias JidoBrowser.Error

  @impl true
  def run(params, context) do
    with {:ok, session} <- ActionHelpers.get_session(context) do
      selector = params.selector
      all = Map.get(params, :all, false)

      script =
        if all do
          """
          (function() {
            const selector = #{Jason.encode!(selector)};
            return Array.from(document.querySelectorAll(selector)).map(el => el.innerText || '');
          })()
          """
        else
          """
          (function() {
            const selector = #{Jason.encode!(selector)};
            const el = document.querySelector(selector);
            return el ? el.innerText || '' : null;
          })()
          """
        end

      case JidoBrowser.evaluate(session, script, []) do
        {:ok, _updated_session, %{result: nil}} ->
          {:error, Error.element_error("get_text", selector, "Element not found")}

        {:ok, updated_session, %{result: texts}} when is_list(texts) ->
          {:ok, %{status: "success", selector: selector, texts: texts, session: updated_session}}

        {:ok, updated_session, %{result: text}} ->
          {:ok, %{status: "success", selector: selector, text: text, session: updated_session}}

        {:error, reason} ->
          {:error, Error.element_error("get_text", selector, reason)}
      end
    end
  end
end
