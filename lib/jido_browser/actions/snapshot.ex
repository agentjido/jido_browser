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

  use Jido.Action,
    name: "browser_snapshot",
    description: "Get comprehensive LLM-friendly snapshot of the current page state",
    category: "Browser",
    tags: ["browser", "snapshot", "observe", "page", "web", "ai"],
    vsn: "2.0.0",
    schema: [
      include_links: [type: :boolean, default: true, doc: "Include extracted links"],
      include_forms: [type: :boolean, default: true, doc: "Include form field info"],
      include_headings: [type: :boolean, default: true, doc: "Include heading structure"],
      max_content_length: [type: :integer, default: 50_000, doc: "Truncate content at this length"],
      selector: [type: :string, default: "body", doc: "CSS selector to scope extraction"]
    ]

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
