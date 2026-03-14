defmodule Jido.Browser.Actions.WaitForSelector do
  @moduledoc """
  Jido Action for waiting for an element to appear, disappear, or change visibility.

  ## Usage with Jido Agent

      # In your agent's tool list
      tools: [Jido.Browser.Actions.WaitForSelector]

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
    vsn: "2.0.0",
    schema: [
      selector: [type: :string, required: true, doc: "CSS selector to wait for"],
      state: [
        type: {:in, [:attached, :visible, :hidden, :detached]},
        default: :visible,
        doc: "State to wait for: :attached, :visible, :hidden, or :detached"
      ],
      timeout: [type: :integer, default: 30_000, doc: "Maximum wait time in milliseconds"]
    ]

  alias Jido.Browser.ActionHelpers
  alias Jido.Browser.Error

  @impl true
  def run(params, context) do
    with {:ok, session} <- ActionHelpers.get_session(context) do
      selector = params.selector
      state = params[:state] || :visible
      timeout = params[:timeout] || 30_000

      case Jido.Browser.wait_for_selector(session, selector, state: state, timeout: timeout) do
        {:ok, updated_session, data} ->
          handle_wait_result(selector, state, updated_session, data)

        {:error, reason} ->
          {:error, Error.element_error("wait_for_selector", selector, reason)}
      end
    end
  end

  defp handle_wait_result(selector, state, updated_session, data) do
    result = ActionHelpers.unwrap_result(data)

    if ActionHelpers.get_value(result, :found) == false do
      {:error,
       Error.element_error(
         "wait_for_selector",
         selector,
         ActionHelpers.get_value(result, :error) || "Selector condition not met"
       )}
    else
      elapsed = ActionHelpers.get_value(result, :elapsed) || 0
      {:ok, %{status: "success", selector: selector, state: state, elapsed_ms: elapsed, session: updated_session}}
    end
  end
end
