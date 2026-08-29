defmodule Jido.Browser.Actions.Snapshot do
  @moduledoc """
  Jido Action for comprehensive page observation.

  This is the most important action for AI agents - it provides a complete view
  of the current page state including content, links, forms, and structure.
  The output is optimized for LLM consumption and decision-making.

  ## Usage with Jido Agent

      # In your agent's tool list
      tools: [Jido.Browser.Actions.Snapshot]

      # The agent can then call:
      # snapshot()
      # snapshot(selector: "main", include_forms: false)
      # snapshot(max_content_length: 10000)

  """

  use Jido.Browser.Action,
    name: "browser_snapshot",
    description: "Get comprehensive LLM-friendly snapshot of the current page state",
    schema:
      Zoi.object(%{
        include_links: Zoi.boolean(description: "Include extracted links") |> Zoi.default(true) |> Zoi.optional(),
        include_forms: Zoi.boolean(description: "Include form field info") |> Zoi.default(true) |> Zoi.optional(),
        include_headings: Zoi.boolean(description: "Include heading structure") |> Zoi.default(true) |> Zoi.optional(),
        max_content_length:
          Zoi.integer(description: "Truncate content at this length")
          |> Zoi.default(50_000)
          |> Zoi.optional(),
        selector:
          Zoi.string(description: "CSS selector to scope extraction")
          |> Zoi.default("body")
          |> Zoi.optional()
      }),
    output_schema:
      Zoi.object(%{
        status: Zoi.literal("success"),
        session: Zoi.any(),
        url: Zoi.string() |> Zoi.nullish(),
        title: Zoi.string() |> Zoi.nullish(),
        origin: Zoi.string() |> Zoi.nullish(),
        snapshot: Zoi.string() |> Zoi.optional(),
        content: Zoi.string() |> Zoi.optional(),
        refs: Zoi.map() |> Zoi.optional(),
        links: Zoi.list(Zoi.map()) |> Zoi.optional(),
        forms: Zoi.list(Zoi.map()) |> Zoi.optional(),
        headings: Zoi.list(Zoi.map()) |> Zoi.optional(),
        raw: Zoi.map() |> Zoi.optional()
      })

  alias Jido.Browser.ActionHelpers
  alias Jido.Browser.Error

  @impl true
  def run(params, context) do
    with {:ok, session} <- ActionHelpers.get_session(context) do
      opts =
        params
        |> Keyword.new()
        |> Keyword.take([
          :selector,
          :max_content_length,
          :include_links,
          :include_forms,
          :include_headings
        ])

      session
      |> Jido.Browser.snapshot(opts)
      |> handle_snapshot_result()
    end
  end

  defp handle_snapshot_result({:ok, session, result}) when is_map(result) do
    snapshot = ActionHelpers.unwrap_result(result)
    {:ok, snapshot |> Map.put(:status, "success") |> Map.put(:session, session)}
  end

  defp handle_snapshot_result({:error, reason}) do
    {:error, Error.adapter_error("Snapshot failed", %{reason: reason})}
  end
end
