defmodule Jido.Browser.Actions.LoadState do
  @moduledoc """
  Jido Action for restoring browser session state from disk.
  """

  use Jido.Action,
    name: "browser_load_state",
    description: "Load browser session state from a file",
    category: "Browser",
    tags: ["browser", "state", "session"],
    vsn: "2.0.0",
    schema: [
      path: [type: :string, required: true, doc: "Filesystem path of the saved session state"],
      timeout: [type: :integer, doc: "Timeout in milliseconds"]
    ]

  alias Jido.Browser.ActionHelpers
  alias Jido.Browser.Error

  @impl true
  def run(params, context) do
    with {:ok, session} <- ActionHelpers.get_session(context) do
      opts = if params[:timeout], do: [timeout: params[:timeout]], else: []

      case Jido.Browser.load_state(session, params.path, opts) do
        {:ok, updated_session, result} ->
          {:ok,
           %{
             status: "success",
             path: params.path,
             result: result,
             session: updated_session
           }}

        {:error, reason} ->
          {:error, Error.adapter_error("Failed to load browser state", %{reason: reason, path: params.path})}
      end
    end
  end
end
