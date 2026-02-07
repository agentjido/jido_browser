defmodule JidoBrowser.Actions.SearchWeb do
  @moduledoc """
  Self-contained action that searches the web and returns structured results.

  Uses DuckDuckGo's HTML interface to perform searches and extract
  structured results (title, URL, snippet) without API keys.

  ## Usage with Jido Agent

      tools: [JidoBrowser.Actions.SearchWeb]

      # The agent can then call:
      # search_web(query: "elixir genserver tutorial")
      # search_web(query: "weather api", max_results: 5)

  """

  use Jido.Action,
    name: "search_web",
    description:
      "Search the web using DuckDuckGo and return structured results " <>
        "with titles, URLs, and snippets. No API key required.",
    category: "Browser",
    tags: ["browser", "web", "search", "duckduckgo"],
    vsn: "1.0.0",
    schema: [
      query: [type: :string, required: true, doc: "Search query"],
      max_results: [type: :integer, default: 10, doc: "Maximum number of results to return"]
    ]

  alias JidoBrowser.Error

  @impl true
  def run(params, _context) do
    query = params.query
    max_results = Map.get(params, :max_results, 10)
    search_url = "https://html.duckduckgo.com/html/?q=#{URI.encode_www_form(query)}"

    case JidoBrowser.start_session(headless: true) do
      {:ok, session} ->
        try do
          with {:ok, session, _nav_result} <- JidoBrowser.navigate(session, search_url) do
            js = extract_results_js(max_results)

            case JidoBrowser.evaluate(session, js, []) do
              {:ok, _session, %{result: results}} when is_list(results) ->
                {:ok, %{query: query, results: results, count: length(results)}}

              {:ok, _session, %{result: result}} when is_binary(result) ->
                case Jason.decode(result) do
                  {:ok, results} when is_list(results) ->
                    {:ok, %{query: query, results: results, count: length(results)}}

                  _ ->
                    {:ok, %{query: query, results: [], count: 0}}
                end

              {:ok, _session, _other} ->
                {:ok, %{query: query, results: [], count: 0}}

              {:error, reason} ->
                {:error, Error.adapter_error("Search extraction failed", %{reason: reason})}
            end
          else
            {:error, reason} ->
              {:error, "Failed to search: #{inspect(reason)}"}
          end
        after
          JidoBrowser.end_session(session)
        end

      {:error, reason} ->
        {:error, "Failed to start browser session: #{inspect(reason)}"}
    end
  end

  defp extract_results_js(max_results) do
    """
    (function(maxResults) {
      var results = [];
      var items = document.querySelectorAll('.result');
      var count = Math.min(items.length, maxResults);
      for (var i = 0; i < count; i++) {
        var item = items[i];
        var linkEl = item.querySelector('.result__a');
        var snippetEl = item.querySelector('.result__snippet');
        if (linkEl) {
          results.push({
            rank: i + 1,
            title: (linkEl.innerText || '').trim(),
            url: linkEl.href || '',
            snippet: snippetEl ? (snippetEl.innerText || '').trim() : ''
          });
        }
      }
      return results;
    })(#{max_results})
    """
  end
end
