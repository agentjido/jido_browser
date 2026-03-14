defmodule Jido.Browser.Actions.NewTab do
  @moduledoc """
  Jido Action for opening a new browser tab.
  """

  use Jido.Action,
    name: "browser_new_tab",
    description: "Open a new browser tab",
    category: "Browser",
    tags: ["browser", "tabs", "navigation"],
    vsn: "2.0.0",
    schema: [
      url: [type: :string, doc: "Optional URL to open in the new tab"],
      timeout: [type: :integer, doc: "Timeout in milliseconds"]
    ]

  alias Jido.Browser.ActionHelpers
  alias Jido.Browser.Error

  @impl true
  def run(params, context) do
    with {:ok, session} <- ActionHelpers.get_session(context) do
      opts = if params[:timeout], do: [timeout: params[:timeout]], else: []

      case Jido.Browser.new_tab(session, params[:url], opts) do
        {:ok, updated_session, result} ->
          {:ok,
           %{
             status: "success",
             url: params[:url],
             result: result,
             session: updated_session
           }}

        {:error, reason} ->
          {:error, Error.adapter_error("Failed to open a new tab", %{reason: reason, url: params[:url]})}
      end
    end
  end
end
