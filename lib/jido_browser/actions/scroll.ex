defmodule JidoBrowser.Actions.Scroll do
  @moduledoc """
  Jido Action for scrolling the page.

  ## Usage with Jido Agent

      # In your agent's tool list
      tools: [JidoBrowser.Actions.Scroll]

      # The agent can then call:
      # scroll(direction: :down)
      # scroll(direction: :top)
      # scroll(x: 0, y: 500)
      # scroll(selector: "#target-element")

  """

  use Jido.Action,
    name: "browser_scroll",
    description: "Scroll the page by pixels, to preset positions, or to an element",
    category: "Browser",
    tags: ["browser", "interaction", "scroll", "web"],
    vsn: "1.0.0",
    schema: [
      x: [type: :integer, doc: "Horizontal scroll pixels"],
      y: [type: :integer, doc: "Vertical scroll pixels"],
      direction: [
        type: {:in, [:up, :down, :top, :bottom]},
        doc: "Preset scroll direction"
      ],
      selector: [type: :string, doc: "CSS selector to scroll element into view"]
    ]

  alias JidoBrowser.ActionHelpers
  alias JidoBrowser.Error

  @impl true
  def run(params, context) do
    with {:ok, session} <- ActionHelpers.get_session(context) do
      script = build_scroll_script(params)

      case JidoBrowser.evaluate(session, script, []) do
        {:ok, updated_session, %{result: result}} ->
          {:ok, %{status: "success", result: result, session: updated_session}}

        {:error, reason} ->
          {:error, Error.adapter_error("Scroll failed", %{reason: reason})}
      end
    end
  end

  defp build_scroll_script(%{selector: selector}) when is_binary(selector) do
    """
    (() => {
      const el = document.querySelector(#{inspect(selector)});
      if (el) {
        el.scrollIntoView({behavior: 'smooth', block: 'center'});
        return {scrolled: true, selector: #{inspect(selector)}};
      }
      return {scrolled: false, error: 'Element not found'};
    })()
    """
  end

  defp build_scroll_script(%{direction: direction}) when direction in [:up, :down, :top, :bottom] do
    case direction do
      :top ->
        "(() => { window.scrollTo(0, 0); return {scrolled: true, direction: 'top'}; })()"

      :bottom ->
        "(() => { window.scrollTo(0, document.body.scrollHeight); return {scrolled: true, direction: 'bottom'}; })()"

      :up ->
        "(() => { window.scrollBy(0, -500); return {scrolled: true, direction: 'up', pixels: -500}; })()"

      :down ->
        "(() => { window.scrollBy(0, 500); return {scrolled: true, direction: 'down', pixels: 500}; })()"
    end
  end

  defp build_scroll_script(params) do
    x = Map.get(params, :x, 0)
    y = Map.get(params, :y, 0)

    "(() => { window.scrollBy(#{x}, #{y}); return {scrolled: true, x: #{x}, y: #{y}}; })()"
  end
end
