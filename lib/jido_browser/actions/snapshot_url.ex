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

  use Jido.Browser.Action,
    name: "snapshot_url",
    description:
      "Navigate to a URL and return a comprehensive LLM-friendly snapshot " <>
        "including content, links, forms, and heading structure. Manages browser session automatically.",
    category: "Browser",
    tags: ["browser", "web", "snapshot", "observe", "ai"],
    vsn: "2.0.0",
    schema:
      Zoi.object(%{
        url: Zoi.string(description: "The URL to snapshot"),
        selector:
          Zoi.string(description: "CSS selector to scope extraction")
          |> Zoi.default("body")
          |> Zoi.optional(),
        include_links: Zoi.boolean(description: "Include extracted links") |> Zoi.default(true) |> Zoi.optional(),
        include_forms: Zoi.boolean(description: "Include form field info") |> Zoi.default(true) |> Zoi.optional(),
        include_headings: Zoi.boolean(description: "Include heading structure") |> Zoi.default(true) |> Zoi.optional(),
        max_content_length:
          Zoi.integer(description: "Truncate content at this length")
          |> Zoi.default(50_000)
          |> Zoi.optional(),
        pool: Zoi.any(description: "Optional warm session pool name") |> Zoi.optional(),
        checkout_timeout: Zoi.integer(description: "Warm pool checkout timeout in ms") |> Zoi.optional(),
        adapter: Zoi.atom(description: "Browser adapter module") |> Zoi.optional(),
        headless: Zoi.boolean(description: "Run in headless mode") |> Zoi.optional(),
        timeout: Zoi.integer(description: "Default browser timeout in ms") |> Zoi.optional()
      })

  alias Jido.Browser.ActionHelpers

  @impl true
  def run(params, context) do
    url = params.url
    selector = Map.get(params, :selector, "body")
    include_links = Map.get(params, :include_links, true)
    include_forms = Map.get(params, :include_forms, true)
    include_headings = Map.get(params, :include_headings, true)
    max_content_length = Map.get(params, :max_content_length, 50_000)
    start_opts = session_start_opts(params, context)

    case Jido.Browser.start_session(start_opts) do
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

  defp session_start_opts(params, context) do
    []
    |> maybe_put(:adapter, session_option(params, context, :adapter))
    |> maybe_put(:headless, session_option(params, context, :headless))
    |> maybe_put(:timeout, session_option(params, context, :timeout))
    |> maybe_put(:pool, session_option(params, context, :pool))
    |> maybe_put(:checkout_timeout, session_option(params, context, :checkout_timeout))
  end

  defp session_option(params, context, key) do
    case Map.fetch(params, key) do
      {:ok, nil} -> get_in(context, [:skill_state, key])
      {:ok, value} -> value
      :error -> get_in(context, [:skill_state, key])
    end
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
end
