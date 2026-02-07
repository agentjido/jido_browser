defmodule JidoBrowser.Actions.SearchWeb do
  @moduledoc """
  Self-contained action that searches the web and returns structured results.

  Uses DuckDuckGo's HTML interface via the Web adapter (Firefox-based)
  to avoid CAPTCHA blocks that headless Chrome triggers.

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

  @impl true
  def run(params, _context) do
    query = params.query
    max_results = Map.get(params, :max_results, 10)
    search_url = "https://html.duckduckgo.com/html/?q=#{URI.encode_www_form(query)}"

    case JidoBrowser.start_session(adapter: JidoBrowser.Adapters.Web) do
      {:ok, session} ->
        try do
          case JidoBrowser.navigate(session, search_url) do
            {:ok, _session, %{content: content}} ->
              results = parse_results(content, max_results)
              {:ok, %{query: query, results: results, count: length(results)}}

            {:ok, _session, _other} ->
              {:ok, %{query: query, results: [], count: 0}}

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

  defp parse_results(content, max_results) do
    content
    |> String.split(~r/\n-{10,}\n/)
    |> Enum.drop(1)
    |> Enum.chunk_every(2)
    |> Enum.flat_map(fn chunk -> parse_result_chunk(chunk) end)
    |> Enum.reject(&ad_result?/1)
    |> Enum.with_index(1)
    |> Enum.map(fn {result, rank} -> Map.put(result, :rank, rank) end)
    |> Enum.take(max_results)
  end

  defp parse_result_chunk([title_section | rest]) do
    title_line = String.trim(title_section)

    case extract_title_and_url(title_line) do
      {title, url} ->
        snippet =
          case rest do
            [body | _] -> extract_snippet(body)
            _ -> ""
          end

        [%{title: title, url: url, snippet: snippet}]

      nil ->
        []
    end
  end

  defp parse_result_chunk(_), do: []

  defp extract_title_and_url(text) do
    case Regex.run(~r/^(.+?)\s*\(/, text) do
      [_, title] ->
        url = extract_url(text)
        if url, do: {String.trim(title), url}, else: nil

      _ ->
        nil
    end
  end

  defp extract_url(text) do
    cond do
      match = Regex.run(~r/uddg=(https?%3A%2F%2F[^&\s]+)/, text) ->
        [_, encoded] = match
        URI.decode_www_form(encoded)

      match = Regex.run(~r/\(\s*(https?:\/\/[^\s)]+)\s*\)/, text) ->
        [_, url] = match
        url

      true ->
        nil
    end
  end

  defp ad_result?(%{url: url}) do
    String.contains?(url, "duckduckgo.com/y.js") or
      String.contains?(url, "bing.com/aclick")
  end

  defp extract_snippet(body) do
    body
    |> String.replace(~r/\(\s*\/\/duckduckgo\.com[^)]*\)/, "")
    |> String.replace(~r/&rut=[a-f0-9]+\s*\)/, "")
    |> String.split("\n")
    |> Enum.reject(fn line ->
      trimmed = String.trim(line)

      trimmed == "" or
        String.starts_with?(trimmed, "(") or
        String.contains?(trimmed, "duckduckgo.com") or
        String.match?(trimmed, ~r/^&rut=/) or
        String.match?(trimmed, ~r/^\*?\*?[a-z\-]+\.[a-z].*\.[a-z]/) or
        String.match?(trimmed, ~r/^http/)
    end)
    |> Enum.map_join(" ", &String.trim/1)
    |> String.replace(~r/\*/, "")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end
end
