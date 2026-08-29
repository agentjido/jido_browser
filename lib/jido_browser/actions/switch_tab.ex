defmodule Jido.Browser.Actions.SwitchTab do
  @moduledoc """
  Jido Action for switching to a specific browser tab.
  """

  use Jido.Browser.Action,
    name: "browser_switch_tab",
    description: "Switch to another browser tab",
    schema:
      Zoi.object(%{
        index: Zoi.integer(description: "Tab index to activate"),
        timeout: Zoi.integer(description: "Timeout in milliseconds") |> Zoi.optional()
      }),
    output_schema:
      Zoi.object(%{
        status: Zoi.literal("success"),
        index: Zoi.integer(),
        result: Zoi.map(),
        session: Zoi.any()
      })

  alias Jido.Browser.ActionHelpers
  alias Jido.Browser.Error

  @impl true
  def run(params, context) do
    with {:ok, session} <- ActionHelpers.get_session(context) do
      opts = if params[:timeout], do: [timeout: params[:timeout]], else: []

      case Jido.Browser.switch_tab(session, params.index, opts) do
        {:ok, updated_session, result} ->
          {:ok,
           %{
             status: "success",
             index: params.index,
             result: result,
             session: updated_session
           }}

        {:error, reason} ->
          {:error, Error.adapter_error("Failed to switch browser tabs", %{reason: reason, index: params.index})}
      end
    end
  end
end
