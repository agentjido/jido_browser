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

  use Jido.Browser.Action,
    name: "browser_start_session",
    description: "Start a new browser session",
    category: "Browser",
    tags: ["browser", "session", "lifecycle"],
    vsn: "2.0.0",
    schema:
      Zoi.object(%{
        headless: Zoi.boolean(description: "Run in headless mode") |> Zoi.optional(),
        timeout: Zoi.integer(description: "Default timeout in ms") |> Zoi.optional(),
        adapter: Zoi.atom(description: "Browser adapter module") |> Zoi.optional(),
        pool: Zoi.any(description: "Optional warm session pool name") |> Zoi.optional(),
        checkout_timeout: Zoi.integer(description: "Warm pool checkout timeout in ms") |> Zoi.optional()
      })

  alias Jido.Browser.Error

  @impl true
  def run(params, context) do
    opts = [
      headless: session_option(params, context, :headless, true),
      timeout: session_option(params, context, :timeout, 30_000)
    ]

    opts = maybe_put(opts, :adapter, session_option(params, context, :adapter, nil))
    opts = maybe_put(opts, :pool, session_option(params, context, :pool, nil))
    opts = maybe_put(opts, :checkout_timeout, session_option(params, context, :checkout_timeout, nil))

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

  defp session_option(params, context, key, default) do
    case Map.fetch(params, key) do
      {:ok, nil} -> context_option(context, key, default)
      {:ok, value} -> value
      :error -> context_option(context, key, default)
    end
  end

  defp context_option(context, key, default) do
    case get_in(context, [:skill_state, key]) do
      nil -> default
      value -> value
    end
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
end
