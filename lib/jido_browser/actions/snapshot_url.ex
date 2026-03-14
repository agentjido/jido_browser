defmodule Jido.Browser.Actions.SnapshotUrl do
  @moduledoc """
  Self-contained action that navigates to a URL and returns a comprehensive
  LLM-friendly snapshot of the page state.

  Combines navigation with the full Snapshot extraction (content, links,
  forms, headings) in a single call with automatic session management.

  When the adapter supports JavaScript evaluation (e.g. Vibium), returns
  a rich snapshot with structured links, forms, and headings. When using
  a text-only adapter (e.g. Web), falls back to content extraction via
  ReadPage-style markdown output.

  ## Usage with Jido Agent

      tools: [Jido.Browser.Actions.SnapshotUrl]

      # The agent can then call:
      # snapshot_url(url: "https://example.com")
      # snapshot_url(url: "https://example.com", selector: "main", include_forms: false)

  """

  use Jido.Action,
    name: "snapshot_url",
    description:
      "Navigate to a URL and return a comprehensive LLM-friendly snapshot " <>
        "including content, links, forms, and heading structure. Manages browser session automatically.",
    category: "Browser",
    tags: ["browser", "web", "snapshot", "observe", "ai"],
    vsn: "2.0.0",
    schema: [
      url: [type: :string, required: true, doc: "The URL to snapshot"],
      selector: [type: :string, default: "body", doc: "CSS selector to scope extraction"],
      include_links: [type: :boolean, default: true, doc: "Include extracted links"],
      include_forms: [type: :boolean, default: true, doc: "Include form field info"],
      include_headings: [type: :boolean, default: true, doc: "Include heading structure"],
      max_content_length: [type: :integer, default: 50_000, doc: "Truncate content at this length"]
    ]

  alias Jido.Browser.ActionHelpers

  @impl true
  def run(params, _context) do
    url = params.url
    selector = Map.get(params, :selector, "body")
    include_links = Map.get(params, :include_links, true)
    include_forms = Map.get(params, :include_forms, true)
    include_headings = Map.get(params, :include_headings, true)
    max_content_length = Map.get(params, :max_content_length, 50_000)

    case Jido.Browser.start_session() do
      {:ok, session} ->
        try do
          perform_snapshot(session, url, selector, include_links, include_forms, include_headings, max_content_length)
        after
          Jido.Browser.end_session(session)
        end

      {:error, reason} ->
        {:error, "Failed to start browser session: #{inspect(reason)}"}
    end
  end

  defp perform_snapshot(session, url, selector, include_links, include_forms, include_headings, max_content_length) do
    case Jido.Browser.navigate(session, url) do
      {:ok, session, _nav_result} ->
        evaluate_snapshot(session, url, selector, include_links, include_forms, include_headings, max_content_length)

      {:error, reason} ->
        {:error, "Failed to navigate to #{url}: #{inspect(reason)}"}
    end
  end

  defp evaluate_snapshot(session, url, selector, include_links, include_forms, include_headings, max_content_length) do
    opts = [
      selector: selector,
      include_links: include_links,
      include_forms: include_forms,
      include_headings: include_headings,
      max_content_length: max_content_length
    ]

    case Jido.Browser.snapshot(session, opts) do
      {:ok, _session, result} when is_map(result) ->
        {:ok, result |> ActionHelpers.unwrap_result() |> Map.put(:status, "success")}

      {:error, _reason} ->
        fallback_read_page(session, url, selector, max_content_length)
    end
  end

  defp fallback_read_page(session, url, selector, max_content_length) do
    case Jido.Browser.extract_content(session, selector: selector, format: :markdown) do
      {:ok, _session, %{content: content}} ->
        truncated = String.slice(content, 0, max_content_length)

        {:ok,
         %{
           url: url,
           content: truncated,
           status: "success",
           fallback: true
         }}

      {:error, reason} ->
        {:error, "Snapshot failed and fallback extraction also failed: #{inspect(reason)}"}
    end
  end
end
