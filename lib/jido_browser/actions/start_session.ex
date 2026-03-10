defmodule Jido.Browser.Actions.StartSession do
  @moduledoc """
  Jido Action for starting a new browser session.

  ## Usage with Jido Agent

      # In your agent's tool list
      tools: [Jido.Browser.Actions.StartSession]

      # The agent can then call:
      # start_session(headless: true, timeout: 30000)

  The returned session should be stored in skill state for use by other browser actions.
  """

  use Jido.Action,
    name: "browser_start_session",
    description: "Start a new browser session",
    category: "Browser",
    tags: ["browser", "session", "lifecycle"],
    vsn: "2.0.0",
    schema: [
      headless: [type: :boolean, default: true, doc: "Run in headless mode"],
      timeout: [type: :integer, default: 30_000, doc: "Default timeout in ms"],
      adapter: [type: :atom, doc: "Browser adapter module"]
    ]

  alias Jido.Browser.Error

  @impl true
  def run(params, _context) do
    opts = [
      headless: Map.get(params, :headless, true),
      timeout: Map.get(params, :timeout, 30_000)
    ]

    opts = if params[:adapter], do: [{:adapter, params[:adapter]} | opts], else: opts

    case Jido.Browser.start_session(opts) do
      {:ok, session} ->
        {:ok,
         %{
           status: "success",
           session: session,
           adapter: session.adapter |> to_string(),
           message: "Browser session started"
         }}

      {:error, reason} ->
        {:error, Error.adapter_error("Failed to start session", %{reason: reason})}
    end
  end
end
