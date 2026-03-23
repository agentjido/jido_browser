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
      adapter: [type: :atom, doc: "Browser adapter module"],
      pool: [type: :any, doc: "Optional warm session pool name"],
      checkout_timeout: [type: :integer, default: 5_000, doc: "Warm pool checkout timeout in ms"]
    ]

  alias Jido.Browser.Error

  @impl true
  def run(params, context) do
    opts = [
      headless: Map.get(params, :headless, true),
      timeout: Map.get(params, :timeout, 30_000)
    ]

    opts = if params[:adapter], do: [{:adapter, params[:adapter]} | opts], else: opts
    opts = maybe_put_context_default(opts, :pool, params[:pool], context)
    opts = maybe_put_context_default(opts, :checkout_timeout, params[:checkout_timeout], context)

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

  defp maybe_put_context_default(opts, key, explicit, _context) when not is_nil(explicit) do
    Keyword.put(opts, key, explicit)
  end

  defp maybe_put_context_default(opts, key, _explicit, context) do
    case get_in(context, [:skill_state, key]) do
      nil -> opts
      value -> Keyword.put(opts, key, value)
    end
  end
end
