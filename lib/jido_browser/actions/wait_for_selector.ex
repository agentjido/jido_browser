defmodule JidoBrowser.Actions.WaitForSelector do
  @moduledoc """
  Jido Action for waiting for an element to appear, disappear, or change visibility.

  ## Usage with Jido Agent

      # In your agent's tool list
      tools: [JidoBrowser.Actions.WaitForSelector]

      # The agent can then call:
      # wait_for_selector(selector: "#modal")
      # wait_for_selector(selector: ".loading", state: :hidden)
      # wait_for_selector(selector: "#content", state: :visible, timeout: 5000)

  """

  use Jido.Action,
    name: "browser_wait_for_selector",
    description: "Wait for an element to appear, disappear, or change visibility state",
    category: "Browser",
    tags: ["browser", "wait", "sync", "web"],
    vsn: "1.0.0",
    schema: [
      selector: [type: :string, required: true, doc: "CSS selector to wait for"],
      state: [
        type: {:in, [:attached, :visible, :hidden, :detached]},
        default: :visible,
        doc: "State to wait for: :attached, :visible, :hidden, or :detached"
      ],
      timeout: [type: :integer, default: 30_000, doc: "Maximum wait time in milliseconds"]
    ]

  alias JidoBrowser.ActionHelpers
  alias JidoBrowser.Error

  @impl true
  def run(params, context) do
    with {:ok, session} <- ActionHelpers.get_session(context) do
      selector = params.selector
      state = params[:state] || :visible
      timeout = params[:timeout] || 30_000

      js = build_wait_js(selector, state, timeout)

      case JidoBrowser.evaluate(session, js, []) do
        {:ok, updated_session, %{result: %{"found" => true, "elapsed" => elapsed}}} ->
          {:ok, %{status: "success", selector: selector, state: state, elapsed_ms: elapsed, session: updated_session}}

        {:ok, updated_session, %{result: %{"found" => true} = result}} ->
          elapsed = Map.get(result, "elapsed", 0)
          {:ok, %{status: "success", selector: selector, state: state, elapsed_ms: elapsed, session: updated_session}}

        {:error, reason} ->
          {:error, Error.element_error("wait_for_selector", selector, reason)}
      end
    end
  end

  defp build_wait_js(selector, state, timeout) do
    state_str = Atom.to_string(state)
    escaped_selector = String.replace(selector, "'", "\\'")

    """
    (function waitForSelector(sel, state, timeout) {
      const start = Date.now();
      return new Promise((resolve, reject) => {
        function check() {
          const el = document.querySelector(sel);
          const elapsed = Date.now() - start;
          if (elapsed > timeout) {
            reject(new Error('Timeout waiting for ' + sel));
            return;
          }
          let found = false;
          if (state === 'attached') found = !!el;
          else if (state === 'detached') found = !el;
          else if (state === 'visible') found = el && el.offsetParent !== null;
          else if (state === 'hidden') found = !el || el.offsetParent === null;
          
          if (found) resolve({found: true, elapsed: elapsed});
          else setTimeout(check, 100);
        }
        check();
      });
    })('#{escaped_selector}', '#{state_str}', #{timeout})
    """
  end
end
