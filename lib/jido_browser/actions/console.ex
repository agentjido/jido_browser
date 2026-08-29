defmodule Jido.Browser.Actions.Console do
  @moduledoc """
  Jido Action for retrieving browser console messages.
  """

  use Jido.Browser.Action,
    name: "browser_console",
    description: "Read browser console messages",
    schema: Zoi.object(%{timeout: Zoi.integer(description: "Timeout in milliseconds") |> Zoi.optional()}),
    output_schema:
      Zoi.object(%{
        status: Zoi.literal("success"),
        messages: Zoi.list(Zoi.map()),
        result: Zoi.map(),
        session: Zoi.any()
      })

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
