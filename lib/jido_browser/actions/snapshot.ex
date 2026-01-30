defmodule JidoBrowser.Actions.Snapshot do
  @moduledoc """
  Jido Action for comprehensive page observation.

  This is the most important action for AI agents - it provides a complete view
  of the current page state including content, links, forms, and structure.
  The output is optimized for LLM consumption and decision-making.

  ## Usage with Jido Agent

      # In your agent's tool list
      tools: [JidoBrowser.Actions.Snapshot]

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
    vsn: "1.0.0",
    schema: [
      include_links: [type: :boolean, default: true, doc: "Include extracted links"],
      include_forms: [type: :boolean, default: true, doc: "Include form field info"],
      include_headings: [type: :boolean, default: true, doc: "Include heading structure"],
      max_content_length: [type: :integer, default: 50_000, doc: "Truncate content at this length"],
      selector: [type: :string, default: "body", doc: "CSS selector to scope extraction"]
    ]

  alias JidoBrowser.ActionHelpers
  alias JidoBrowser.Error

  @impl true
  def run(params, context) do
    with {:ok, session} <- ActionHelpers.get_session(context) do
      include_links = Map.get(params, :include_links, true)
      include_forms = Map.get(params, :include_forms, true)
      include_headings = Map.get(params, :include_headings, true)
      max_content_length = Map.get(params, :max_content_length, 50_000)
      selector = Map.get(params, :selector, "body")

      js = snapshot_js(selector, include_links, include_forms, include_headings, max_content_length)

      session
      |> JidoBrowser.evaluate(js, [])
      |> handle_snapshot_result()
    end
  end

  defp handle_snapshot_result({:ok, session, %{result: result}}) when is_map(result) do
    {:ok, result |> Map.put(:status, "success") |> Map.put(:session, session)}
  end

  defp handle_snapshot_result({:ok, session, %{result: result}}) when is_binary(result) do
    case Jason.decode(result) do
      {:ok, decoded} when is_map(decoded) ->
        {:ok, decoded |> Map.put(:status, "success") |> Map.put(:session, session)}

      _ ->
        {:error, Error.adapter_error("Snapshot returned non-JSON result", %{result: result})}
    end
  end

  defp handle_snapshot_result({:ok, _session, %{result: result}}) do
    {:error, Error.adapter_error("Snapshot returned unexpected result", %{result: result})}
  end

  defp handle_snapshot_result({:error, reason}) do
    {:error, Error.adapter_error("Snapshot failed", %{reason: reason})}
  end

  defp snapshot_js(selector, include_links, include_forms, include_headings, max_content_length) do
    """
    (function snapshot(selector, includeLinks, includeForms, includeHeadings, maxContentLength) {
      const root = document.querySelector(selector) || document.body;

      // Get basic info
      const result = {
        url: window.location.href,
        title: document.title,
        meta: {
          viewport_height: window.innerHeight,
          scroll_height: document.body.scrollHeight,
          scroll_position: window.scrollY
        }
      };

      // Extract text content (simplified markdown)
      result.content = root.innerText.substring(0, maxContentLength);

      // Extract links
      if (includeLinks) {
        result.links = Array.from(root.querySelectorAll('a[href]')).slice(0, 100).map((a, i) => ({
          id: 'link_' + i,
          text: a.innerText.trim().substring(0, 100),
          href: a.href
        }));
      }

      // Extract forms
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

      // Extract headings
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
