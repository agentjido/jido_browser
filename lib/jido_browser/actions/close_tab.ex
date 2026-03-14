defmodule Jido.Browser.Actions.CloseTab do
  @moduledoc """
  Jido Action for closing the current tab or a specific browser tab.
  """

  use Jido.Action,
    name: "browser_close_tab",
    description: "Close a browser tab",
    category: "Browser",
    tags: ["browser", "tabs", "session"],
    vsn: "2.0.0",
    schema: [
      index: [type: :integer, doc: "Optional tab index to close"],
      timeout: [type: :integer, doc: "Timeout in milliseconds"]
    ]

  alias Jido.Browser.ActionHelpers
  alias Jido.Browser.Error

  @impl true
  def run(params, context) do
    with {:ok, session} <- ActionHelpers.get_session(context) do
      opts = if params[:timeout], do: [timeout: params[:timeout]], else: []

      case Jido.Browser.close_tab(session, params[:index], opts) do
        {:ok, updated_session, result} ->
          {:ok,
           %{
             status: "success",
             index: params[:index],
             result: result,
             session: updated_session
           }}

        {:error, reason} ->
          {:error, Error.adapter_error("Failed to close browser tab", %{reason: reason, index: params[:index]})}
      end
    end
  end
end
