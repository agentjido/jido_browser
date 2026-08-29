defmodule Jido.Browser.Actions.ListTabs do
  @moduledoc """
  Jido Action for listing the tabs in the current browser session.
  """

  use Jido.Browser.Action,
    name: "browser_list_tabs",
    description: "List open browser tabs",
    schema: Zoi.object(%{timeout: Zoi.integer(description: "Timeout in milliseconds") |> Zoi.optional()}),
    output_schema:
      Zoi.object(%{
        status: Zoi.literal("success"),
        tabs: Zoi.list(Zoi.map()),
        result: Zoi.map(),
        session: Zoi.any()
      })

  alias Jido.Browser.ActionHelpers
  alias Jido.Browser.Error

  @impl true
  def run(params, context) do
    with {:ok, session} <- ActionHelpers.get_session(context) do
      opts = if params[:timeout], do: [timeout: params[:timeout]], else: []

      case Jido.Browser.list_tabs(session, opts) do
        {:ok, updated_session, result} ->
          tabs = ActionHelpers.get_value(result, :tabs) || result
          {:ok, %{status: "success", tabs: tabs, result: result, session: updated_session}}

        {:error, reason} ->
          {:error, Error.adapter_error("Failed to list browser tabs", %{reason: reason})}
      end
    end
  end
end
