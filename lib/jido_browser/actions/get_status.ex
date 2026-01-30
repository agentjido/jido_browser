defmodule JidoBrowser.Actions.GetStatus do
  @moduledoc """
  Jido Action for getting the current browser session status.

  ## Usage with Jido Agent

      # In your agent's tool list
      tools: [JidoBrowser.Actions.GetStatus]

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
    vsn: "1.0.0",
    schema: []

  alias JidoBrowser.ActionHelpers

  @impl true
  def run(_params, context) do
    with {:ok, session} <- ActionHelpers.get_session(context) do
      case JidoBrowser.evaluate(
             session,
             "({url: window.location.href, title: document.title})",
             []
           ) do
        {:ok, updated_session, %{result: result}} ->
          {:ok,
           %{
             status: "success",
             alive: true,
             url: result["url"],
             title: result["title"],
             adapter: session.adapter |> to_string(),
             session: updated_session
           }}

        {:error, _} ->
          {:ok, %{status: "success", alive: false, url: nil, title: nil}}
      end
    end
  end
end
