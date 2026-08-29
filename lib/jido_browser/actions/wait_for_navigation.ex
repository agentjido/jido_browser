defmodule Jido.Browser.Actions.WaitForNavigation do
  @moduledoc """
  Jido Action for waiting for page navigation to complete.

  ## Usage with Jido Agent

      # In your agent's tool list
      tools: [Jido.Browser.Actions.WaitForNavigation]

      # The agent can then call:
      # wait_for_navigation()
      # wait_for_navigation(url: "/dashboard")
      # wait_for_navigation(url: "success", timeout: 5000)

  """

  use Jido.Browser.Action,
    name: "browser_wait_for_navigation",
    description: "Wait for page navigation to complete",
    schema:
      Zoi.object(%{
        url: Zoi.string(description: "URL pattern to match (substring match)") |> Zoi.optional(),
        timeout:
          Zoi.integer(description: "Maximum wait time in milliseconds")
          |> Zoi.default(30_000)
          |> Zoi.optional()
      })

  alias Jido.Browser.ActionHelpers
  alias Jido.Browser.Error

  @impl true
  def run(params, context) do
    with {:ok, session} <- ActionHelpers.get_session(context) do
      url_pattern = params[:url]
      timeout = params[:timeout] || 30_000

      opts =
        []
        |> Keyword.put(:timeout, timeout)
        |> maybe_put_url(url_pattern)

      case Jido.Browser.wait_for_navigation(session, opts) do
        {:ok, updated_session, data} ->
          result = ActionHelpers.unwrap_result(data)
          url = ActionHelpers.get_value(result, :url) || url_pattern
          elapsed = ActionHelpers.get_value(result, :elapsed) || 0
          {:ok, %{status: "success", url: url, elapsed_ms: elapsed, session: updated_session}}

        {:error, reason} ->
          {:error, Error.navigation_error("wait_for_navigation", reason)}
      end
    end
  end

  defp maybe_put_url(opts, nil), do: opts
  defp maybe_put_url(opts, url_pattern), do: Keyword.put(opts, :url, url_pattern)
end
