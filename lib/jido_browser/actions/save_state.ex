defmodule Jido.Browser.Actions.SaveState do
  @moduledoc """
  Jido Action for persisting the current browser session state to disk.
  """

  use Jido.Action,
    name: "browser_save_state",
    description: "Save browser session state to a file",
    category: "Browser",
    tags: ["browser", "state", "session"],
    vsn: "2.0.0",
    schema: [
      path: [type: :string, required: true, doc: "Filesystem path where session state will be stored"],
      timeout: [type: :integer, doc: "Timeout in milliseconds"]
    ]

  alias Jido.Browser.ActionHelpers
  alias Jido.Browser.Error

  @impl true
  def run(params, context) do
    with {:ok, session} <- ActionHelpers.get_session(context) do
      opts = if params[:timeout], do: [timeout: params[:timeout]], else: []

      case Jido.Browser.save_state(session, params.path, opts) do
        {:ok, updated_session, result} ->
          {:ok,
           %{
             status: "success",
             path: params.path,
             result: result,
             session: updated_session
           }}

        {:error, reason} ->
          {:error, Error.adapter_error("Failed to save browser state", %{reason: reason, path: params.path})}
      end
    end
  end
end
