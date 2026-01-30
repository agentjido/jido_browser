defmodule JidoBrowser.Actions.GetTitle do
  @moduledoc """
  Jido Action for getting the current page title.

  ## Usage with Jido Agent

      # In your agent's tool list
      tools: [JidoBrowser.Actions.GetTitle]

      # The agent can then call:
      # get_title()

  """

  use Jido.Action,
    name: "browser_get_title",
    description: "Get the current page title",
    category: "Browser",
    tags: ["browser", "navigation", "web"],
    vsn: "1.0.0",
    schema: [
      timeout: [type: :integer, doc: "Timeout in milliseconds"]
    ]

  alias JidoBrowser.ActionHelpers
  alias JidoBrowser.Error

  @impl true
  def run(params, context) do
    with {:ok, session} <- ActionHelpers.get_session(context) do
      opts = if params[:timeout], do: [timeout: params[:timeout]], else: []

      case JidoBrowser.evaluate(session, "document.title", opts) do
        {:ok, updated_session, %{result: title}} when is_binary(title) ->
          {:ok, %{status: "success", title: title, session: updated_session}}

        {:ok, updated_session, %{result: %{"value" => title}}} ->
          {:ok, %{status: "success", title: title, session: updated_session}}

        {:ok, updated_session, %{result: result}} ->
          {:ok, %{status: "success", title: to_string(result), session: updated_session}}

        {:error, %Error.AdapterError{} = error} ->
          {:error, error}

        {:error, reason} ->
          {:error, Error.adapter_error("Failed to get title: #{inspect(reason)}")}
      end
    end
  end
end
