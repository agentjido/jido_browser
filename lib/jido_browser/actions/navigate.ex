defmodule Jido.Browser.Actions.Navigate do
  @moduledoc """
  Jido Action for navigating to a URL.

  ## Usage with Jido Agent

      # In your agent's tool list
      tools: [Jido.Browser.Actions.Navigate]

      # The agent can then call:
      # navigate(url: "https://example.com")

  """

  use Jido.Browser.Action,
    name: "browser_navigate",
    description: "Navigate the browser to a URL",
    schema:
      Zoi.object(%{
        url: Zoi.string(description: "The URL to navigate to"),
        timeout: Zoi.integer(description: "Timeout in milliseconds") |> Zoi.optional()
      })

  alias Jido.Browser.ActionHelpers
  alias Jido.Browser.Error

  @impl true
  def run(params, context) do
    with {:ok, session} <- ActionHelpers.get_session(context) do
      case Jido.Browser.navigate(session, params.url, timeout: params[:timeout]) do
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
