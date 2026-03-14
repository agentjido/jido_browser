defmodule Jido.Browser.Actions.GetTitle do
  @moduledoc """
  Jido Action for getting the current page title.

  ## Usage with Jido Agent

      # In your agent's tool list
      tools: [Jido.Browser.Actions.GetTitle]

      # The agent can then call:
      # get_title()

  """

  use Jido.Action,
    name: "browser_get_title",
    description: "Get the current page title",
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

      case Jido.Browser.get_title(session, opts) do
        {:ok, updated_session, result} ->
          build_title_response(updated_session, result)

        {:error, %Error.AdapterError{} = error} ->
          {:error, error}

        {:error, reason} ->
          {:error, Error.adapter_error("Failed to get title: #{inspect(reason)}")}
      end
    end
  end

  defp build_title_response(updated_session, result) do
    title =
      result
      |> ActionHelpers.get_value(:title)
      |> normalize_string()

    {:ok, %{status: "success", title: title, session: updated_session}}
  end

  defp normalize_string(value) when is_binary(value), do: value
  defp normalize_string(value), do: to_string(value)
end
