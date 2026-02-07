defmodule JidoBrowser.Actions.SearchWeb do
  @moduledoc """
  Search the web using the Brave Search API and return structured results.

  Requires a Brave Search API key, configured via application config:

      config :jido_browser, :brave_api_key, "your-key"

  Or via the `BRAVE_SEARCH_API_KEY` environment variable.

  ## Usage with Jido Agent

      tools: [JidoBrowser.Actions.SearchWeb]

      # The agent can then call:
      # search_web(query: "elixir genserver tutorial")
      # search_web(query: "weather api", max_results: 5)

  """

  use Jido.Action,
    name: "search_web",
    description:
      "Search the web using Brave Search API and return structured results " <>
        "with titles, URLs, and snippets.",
    category: "Browser",
    tags: ["browser", "web", "search", "brave"],
    vsn: "1.0.0",
    schema: [
      query: [type: :string, required: true, doc: "Search query"],
      max_results: [type: :integer, default: 10, doc: "Maximum number of results to return (max 20)"],
      country: [type: :string, default: "us", doc: "Country code for results (e.g. us, gb, de)"],
      search_lang: [type: :string, default: "en", doc: "Language code for results"],
      freshness: [type: :string, doc: "Freshness filter: pd (24h), pw (week), pm (month), py (year)"]
    ]

  @brave_api_url "https://api.search.brave.com/res/v1/web/search"

  @impl true
  def run(params, _context) do
    with {:ok, api_key} <- get_api_key() do
      query = params.query
      max_results = min(Map.get(params, :max_results, 10), 20)

      query_params =
        %{
          q: query,
          count: max_results,
          country: Map.get(params, :country, "us"),
          search_lang: Map.get(params, :search_lang, "en"),
          text_decorations: false
        }
        |> maybe_put(:freshness, Map.get(params, :freshness))

      case Req.get(@brave_api_url,
             headers: [
               {"X-Subscription-Token", api_key},
               {"Accept", "application/json"},
               {"Accept-Encoding", "gzip"}
             ],
             params: query_params,
             receive_timeout: 15_000
           ) do
        {:ok, %Req.Response{status: 200, body: body}} ->
          results = parse_results(body, max_results)
          {:ok, %{query: query, results: results, count: length(results)}}

        {:ok, %Req.Response{status: 401}} ->
          {:error, "Brave Search API: invalid API key"}

        {:ok, %Req.Response{status: 429}} ->
          {:error, "Brave Search API: rate limit exceeded"}

        {:ok, %Req.Response{status: status, body: body}} ->
          {:error, "Brave Search API error (#{status}): #{inspect(body)}"}

        {:error, reason} ->
          {:error, "Brave Search API request failed: #{inspect(reason)}"}
      end
    end
  end

  defp get_api_key do
    case Application.get_env(:jido_browser, :brave_api_key) || System.get_env("BRAVE_SEARCH_API_KEY") do
      nil -> {:error, "Brave Search API key not configured. Set :brave_api_key in :jido_browser config or BRAVE_SEARCH_API_KEY env var."}
      "" -> {:error, "Brave Search API key is empty"}
      key -> {:ok, key}
    end
  end

  defp parse_results(body, max_results) do
    body
    |> get_in(["web", "results"])
    |> case do
      nil -> []
      results -> results
    end
    |> Enum.take(max_results)
    |> Enum.with_index(1)
    |> Enum.map(fn {result, rank} ->
      %{
        rank: rank,
        title: result["title"] || "",
        url: result["url"] || "",
        snippet: result["description"] || "",
        age: result["age"]
      }
    end)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
