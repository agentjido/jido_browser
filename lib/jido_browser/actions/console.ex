defmodule Jido.Browser.Actions.Console do
  @moduledoc """
  Jido Action for retrieving browser console messages.
  """

  use Jido.Action,
    name: "browser_console",
    description: "Read browser console messages",
    category: "Browser",
    tags: ["browser", "diagnostics", "console"],
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

      case Jido.Browser.console(session, opts) do
        {:ok, updated_session, result} ->
          messages = ActionHelpers.get_value(result, :messages) || result
          {:ok, %{status: "success", messages: messages, result: result, session: updated_session}}

        {:error, reason} ->
          {:error, Error.adapter_error("Failed to read browser console", %{reason: reason})}
      end
    end
  end
end
