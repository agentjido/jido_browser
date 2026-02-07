defmodule JidoBrowser.Actions.SnapshotUrl do
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

      tools: [JidoBrowser.Actions.SnapshotUrl]

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
    vsn: "1.0.0",
    schema: [
      url: [type: :string, required: true, doc: "The URL to snapshot"],
      selector: [type: :string, default: "body", doc: "CSS selector to scope extraction"],
      include_links: [type: :boolean, default: true, doc: "Include extracted links"],
      include_forms: [type: :boolean, default: true, doc: "Include form field info"],
      include_headings: [type: :boolean, default: true, doc: "Include heading structure"],
      max_content_length: [type: :integer, default: 50_000, doc: "Truncate content at this length"]
    ]

  @impl true
  def run(params, _context) do
    url = params.url
    selector = Map.get(params, :selector, "body")
    include_links = Map.get(params, :include_links, true)
    include_forms = Map.get(params, :include_forms, true)
    include_headings = Map.get(params, :include_headings, true)
    max_content_length = Map.get(params, :max_content_length, 50_000)

    case JidoBrowser.start_session(adapter: JidoBrowser.Adapters.Web) do
      {:ok, session} ->
        try do
          case JidoBrowser.navigate(session, url) do
            {:ok, session, _nav_result} ->
              js =
                snapshot_js(
                  selector,
                  include_links,
                  include_forms,
                  include_headings,
                  max_content_length
                )

              case JidoBrowser.evaluate(session, js, []) do
                {:ok, _session, %{result: result}} when is_map(result) ->
                  {:ok, Map.put(result, :status, "success")}

                {:ok, _session, %{result: result}} when is_binary(result) ->
                  case Jason.decode(result) do
                    {:ok, decoded} when is_map(decoded) ->
                      {:ok, Map.put(decoded, :status, "success")}

                    _ ->
                      fallback_read_page(session, url, selector, max_content_length)
                  end

                _ ->
                  fallback_read_page(session, url, selector, max_content_length)
              end

            {:error, reason} ->
              {:error, "Failed to navigate to #{url}: #{inspect(reason)}"}
          end
        after
          JidoBrowser.end_session(session)
        end

      {:error, reason} ->
        {:error, "Failed to start browser session: #{inspect(reason)}"}
    end
  end

  defp fallback_read_page(session, url, selector, max_content_length) do
    case JidoBrowser.extract_content(session, selector: selector, format: :markdown) do
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

  defp snapshot_js(selector, include_links, include_forms, include_headings, max_content_length) do
    """
    (function snapshot(selector, includeLinks, includeForms, includeHeadings, maxContentLength) {
      const root = document.querySelector(selector) || document.body;

      const result = {
        url: window.location.href,
        title: document.title,
        meta: {
          viewport_height: window.innerHeight,
          scroll_height: document.body.scrollHeight,
          scroll_position: window.scrollY
        }
      };

      result.content = root.innerText.substring(0, maxContentLength);

      if (includeLinks) {
        result.links = Array.from(root.querySelectorAll('a[href]')).slice(0, 100).map((a, i) => ({
          id: 'link_' + i,
          text: a.innerText.trim().substring(0, 100),
          href: a.href
        }));
      }

      if (includeForms) {
        result.forms = Array.from(root.querySelectorAll('form')).map(form => ({
          id: form.id || null,
          action: form.action,
          method: form.method || 'GET',
          fields: Array.from(form.querySelectorAll('input, select, textarea')).map(f => ({
            name: f.name,
            type: f.type || 'text',
            label: document.querySelector('label[for="' + f.id + '"]')?.innerText || null,
            required: f.required,
            value: f.type === 'password' ? '' : f.value
          }))
        }));
      }

      if (includeHeadings) {
        result.headings = Array.from(root.querySelectorAll('h1,h2,h3,h4,h5,h6')).slice(0, 50).map(h => ({
          level: parseInt(h.tagName.substring(1)),
          text: h.innerText.trim().substring(0, 200)
        }));
      }

      return result;
    })(#{Jason.encode!(selector)}, #{include_links}, #{include_forms}, #{include_headings}, #{max_content_length})
    """
  end
end
