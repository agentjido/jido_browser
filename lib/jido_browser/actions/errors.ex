defmodule Jido.Browser.Actions.Errors do
  @moduledoc """
  Jido Action for retrieving browser/runtime errors.
  """

  use Jido.Browser.Action,
    name: "browser_errors",
    description: "Read browser runtime errors",
    schema: Zoi.object(%{timeout: Zoi.integer(description: "Timeout in milliseconds") |> Zoi.optional()})

  alias Jido.Browser.ActionHelpers
  alias Jido.Browser.Error

  @impl true
  def run(params, context) do
    with {:ok, session} <- ActionHelpers.get_session(context) do
      opts = if params[:timeout], do: [timeout: params[:timeout]], else: []

      case Jido.Browser.errors(session, opts) do
        {:ok, updated_session, result} ->
          errors = ActionHelpers.get_value(result, :errors) || result
          {:ok, %{status: "success", errors: errors, result: result, session: updated_session}}

        {:error, reason} ->
          {:error, Error.adapter_error("Failed to read browser errors", %{reason: reason})}
      end
    end
  end
end
