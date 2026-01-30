defmodule JidoBrowser.Actions.Navigate do
  @moduledoc """
  Jido Action for navigating to a URL.

  ## Usage with Jido Agent

      # In your agent's tool list
      tools: [JidoBrowser.Actions.Navigate]

      # The agent can then call:
      # navigate(url: "https://example.com")

  """

  use Jido.Action,
    name: "browser_navigate",
    description: "Navigate the browser to a URL",
    category: "Browser",
    tags: ["browser", "navigation", "web"],
    vsn: "1.0.0",
    schema: [
      url: [type: :string, required: true, doc: "The URL to navigate to"],
      timeout: [type: :integer, doc: "Timeout in milliseconds"]
    ]

  alias JidoBrowser.ActionHelpers
  alias JidoBrowser.Error

  @impl true
  def run(params, context) do
    with {:ok, session} <- ActionHelpers.get_session(context) do
      case JidoBrowser.navigate(session, params.url, timeout: params[:timeout]) do
        {:ok, updated_session, result} ->
          {:ok, %{status: "success", url: params.url, result: result, session: updated_session}}

        {:error, %Error.NavigationError{} = error} ->
          {:error, error}

        {:error, reason} ->
          {:error, Error.navigation_error(params.url, reason)}
      end
    end
  end
end
