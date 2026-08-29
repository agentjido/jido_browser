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

  use Jido.Browser.Action,
    name: "browser_wait_for_selector",
    description: "Wait for an element to appear, disappear, or change visibility state",
    schema:
      Zoi.object(%{
        selector: Zoi.string(description: "CSS selector to wait for"),
        state:
          Zoi.enum([:attached, :visible, :hidden, :detached],
            description: "State to wait for: :attached, :visible, :hidden, or :detached"
          )
          |> Zoi.default(:visible)
          |> Zoi.optional(),
        timeout:
          Zoi.integer(description: "Maximum wait time in milliseconds")
          |> Zoi.default(30_000)
          |> Zoi.optional()
      }),
    output_schema:
      Zoi.object(%{
        status: Zoi.literal("success"),
        selector: Zoi.string(),
        state: Zoi.enum([:attached, :visible, :hidden, :detached]),
        elapsed_ms: Zoi.integer(gte: 0),
        session: Zoi.any()
      })

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
