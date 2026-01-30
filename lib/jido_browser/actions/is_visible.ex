defmodule JidoBrowser.Actions.IsVisible do
  @moduledoc """
  Jido Action for checking if an element is visible.

  ## Usage with Jido Agent

      # In your agent's tool list
      tools: [JidoBrowser.Actions.IsVisible]

      # The agent can then call:
      # is_visible(selector: "#modal")
      # is_visible(selector: ".loading-spinner")

  """

  use Jido.Action,
    name: "browser_is_visible",
    description: "Check if an element is visible",
    category: "Browser",
    tags: ["browser", "query", "web"],
    vsn: "1.0.0",
    schema: [
      selector: [type: :string, required: true, doc: "CSS selector for the element"]
    ]

  alias JidoBrowser.ActionHelpers
  alias JidoBrowser.Error

  @impl true
  def run(params, context) do
    with {:ok, session} <- ActionHelpers.get_session(context) do
      selector = params.selector

      script = """
      (function() {
        const selector = #{Jason.encode!(selector)};
        const el = document.querySelector(selector);
        if (!el) return {exists: false, visible: false};
        const style = window.getComputedStyle(el);
        const visible = el.offsetParent !== null && 
                        style.visibility !== 'hidden' && 
                        style.display !== 'none';
        return {exists: true, visible: visible};
      })()
      """

      case JidoBrowser.evaluate(session, script, []) do
        {:ok, updated_session, %{result: %{"exists" => exists, "visible" => visible}}} ->
          {:ok, %{exists: exists, visible: visible, session: updated_session}}

        {:ok, updated_session, %{result: %{exists: exists, visible: visible}}} ->
          {:ok, %{exists: exists, visible: visible, session: updated_session}}

        {:error, reason} ->
          {:error, Error.element_error("is_visible", selector, reason)}
      end
    end
  end
end
