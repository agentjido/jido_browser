defmodule Jido.Browser.Actions.GetUrl do
  @moduledoc """
  Jido Action for getting the current page URL.

  ## Usage with Jido Agent

      # In your agent's tool list
      tools: [Jido.Browser.Actions.GetUrl]

      # The agent can then call:
      # get_url()

  """

  use Jido.Action,
    name: "browser_get_url",
    description: "Get the current page URL",
    category: "Browser",
    tags: ["browser", "navigation", "web"],
    vsn: "2.0.0",
    schema: [
      timeout: [type: :integer, doc: "Timeout in milliseconds"]
    ]

  alias Jido.Browser.ActionHelpers
  alias Jido.Browser.Error

  @impl true
  def run(params, context) do
    with {:ok, session} <- ActionHelpers.get_session(context) do
      opts = if params[:timeout], do: [timeout: params[:timeout]], else: []

      case Jido.Browser.evaluate(session, "window.location.href", opts) do
        {:ok, updated_session, %{result: url}} when is_binary(url) ->
          {:ok, %{status: "success", url: url, session: updated_session}}

        {:ok, updated_session, %{result: %{"value" => url}}} ->
          {:ok, %{status: "success", url: url, session: updated_session}}

        {:ok, updated_session, %{result: result}} ->
          {:ok, %{status: "success", url: to_string(result), session: updated_session}}

        {:error, %Error.AdapterError{} = error} ->
          {:error, error}

        {:error, reason} ->
          {:error, Error.adapter_error("Failed to get URL: #{inspect(reason)}")}
      end
    end
  end
end
