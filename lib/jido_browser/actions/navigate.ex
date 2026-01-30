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

  alias JidoBrowser.Error

  @impl true
  def run(params, context) do
    session = get_session(context)

    case JidoBrowser.navigate(session, params.url, timeout: params[:timeout]) do
      {:ok, result} ->
        {:ok, %{status: "success", url: params.url, result: result}}

      {:error, %Error.NavigationError{} = error} ->
        {:error, error}

      {:error, reason} ->
        {:error, Error.navigation_error(params.url, reason)}
    end
  end

  defp get_session(context) do
    context[:session] ||
      context[:browser_session] ||
      get_in(context, [:tool_context, :session]) ||
      raise "No browser session in context. Start one with JidoBrowser.start_session/1"
  end
end
