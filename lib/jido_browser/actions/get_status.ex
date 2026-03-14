defmodule Jido.Browser.Actions.GetStatus do
  @moduledoc """
  Jido Action for getting the current browser session status.

  ## Usage with Jido Agent

      # In your agent's tool list
      tools: [Jido.Browser.Actions.GetStatus]

      # The agent can then call:
      # get_status()

  Returns the current URL, title, and whether the session is alive.
  Requires a browser session in context (via :session, :browser_session, or tool_context).
  """

  use Jido.Action,
    name: "browser_get_status",
    description: "Get current session status (url, title, is_alive)",
    category: "Browser",
    tags: ["browser", "session", "status"],
    vsn: "2.0.0",
    schema: []

  alias Jido.Browser.ActionHelpers

  @impl true
  def run(_params, context) do
    with {:ok, session} <- ActionHelpers.get_session(context) do
      {:ok, updated_session, result} = Jido.Browser.get_status(session)

      {:ok,
       %{
         status: "success",
         alive: ActionHelpers.get_value(result, :alive),
         url: ActionHelpers.get_value(result, :url),
         title: ActionHelpers.get_value(result, :title),
         adapter: session.adapter |> to_string(),
         session: updated_session
       }}
    end
  end
end
