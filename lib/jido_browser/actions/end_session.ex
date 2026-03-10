defmodule Jido.Browser.Actions.EndSession do
  @moduledoc """
  Jido Action for ending a browser session.

  ## Usage with Jido Agent

      # In your agent's tool list
      tools: [Jido.Browser.Actions.EndSession]

      # The agent can then call:
      # end_session()

  Requires a browser session in context (via :session, :browser_session, or tool_context).
  """

  use Jido.Action,
    name: "browser_end_session",
    description: "End the current browser session",
    category: "Browser",
    tags: ["browser", "session", "lifecycle"],
    vsn: "2.0.0",
    schema: []

  alias Jido.Browser.ActionHelpers
  alias Jido.Browser.Error

  @impl true
  def run(_params, context) do
    with {:ok, session} <- ActionHelpers.get_session(context) do
      case Jido.Browser.end_session(session) do
        :ok ->
          {:ok, %{status: "success", message: "Session ended"}}

        {:error, reason} ->
          {:error, Error.adapter_error("Failed to end session", %{reason: reason})}
      end
    end
  end
end
