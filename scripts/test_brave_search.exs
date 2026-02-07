# Brave Search API Test Script
#
# Run with: mix run scripts/test_brave_search.exs
#
# Requires BRAVE_SEARCH_API_KEY in .env or environment

if File.exists?(".env") do
  ".env"
  |> File.read!()
  |> String.split("\n", trim: true)
  |> Enum.each(fn line ->
    case String.split(line, "=", parts: 2) do
      [key, value] ->
        key = String.trim(key)
        value = value |> String.trim() |> String.trim("\"") |> String.trim("'")
        unless String.starts_with?(key, "#"), do: System.put_env(key, value)
      _ -> :ok
    end
  end)

  IO.puts("Loaded .env file")
end

IO.puts("\n" <> String.duplicate("=", 60))
IO.puts("Brave Search API - SearchWeb Action Test")
IO.puts(String.duplicate("=", 60))

# --- Test 1: Basic search ---
IO.puts("\n[1] Basic search: 'elixir programming language'")

case JidoBrowser.Actions.SearchWeb.run(%{query: "elixir programming language", max_results: 5}, %{}) do
  {:ok, %{query: query, results: results, count: count}} ->
    IO.puts("    OK - '#{query}' returned #{count} results\n")

    Enum.each(results, fn r ->
      IO.puts("    #{r.rank}. #{r.title}")
      IO.puts("       #{r.url}")
      IO.puts("       #{String.slice(r.snippet || "", 0..120)}\n")
    end)

  {:error, reason} ->
    IO.puts("    FAIL - #{inspect(reason)}")
    System.halt(1)
end

# --- Test 2: Search with freshness filter ---
IO.puts("\n[2] Search with freshness filter (past week): 'elixir lang news'")

case JidoBrowser.Actions.SearchWeb.run(%{query: "elixir lang news", max_results: 3, freshness: "pw"}, %{}) do
  {:ok, %{query: query, results: results, count: count}} ->
    IO.puts("    OK - '#{query}' returned #{count} results\n")

    Enum.each(results, fn r ->
      IO.puts("    #{r.rank}. #{r.title}")
      IO.puts("       #{r.url}")
      IO.puts("       age: #{r.age || "n/a"}\n")
    end)

  {:error, reason} ->
    IO.puts("    FAIL - #{inspect(reason)}")
    System.halt(1)
end

# --- Test 3: Empty results query ---
IO.puts("\n[3] Obscure query (expect few/no results): 'xyzzy9999qqq'")

case JidoBrowser.Actions.SearchWeb.run(%{query: "xyzzy9999qqq", max_results: 3}, %{}) do
  {:ok, %{query: query, results: _results, count: count}} ->
    IO.puts("    OK - '#{query}' returned #{count} results")

  {:error, reason} ->
    IO.puts("    FAIL - #{inspect(reason)}")
    System.halt(1)
end

# --- Test 4: Missing API key ---
IO.puts("\n[4] Missing API key error handling")

original_key = System.get_env("BRAVE_SEARCH_API_KEY")
original_config = Application.get_env(:jido_browser, :brave_api_key)
System.delete_env("BRAVE_SEARCH_API_KEY")
Application.put_env(:jido_browser, :brave_api_key, nil)

case JidoBrowser.Actions.SearchWeb.run(%{query: "test"}, %{}) do
  {:error, msg} when is_binary(msg) ->
    IO.puts("    OK - got expected error: #{String.slice(msg, 0..80)}")

  other ->
    IO.puts("    FAIL - expected error, got: #{inspect(other)}")
    System.halt(1)
end

if original_key, do: System.put_env("BRAVE_SEARCH_API_KEY", original_key)
if original_config, do: Application.put_env(:jido_browser, :brave_api_key, original_config)

IO.puts("\n" <> String.duplicate("=", 60))
IO.puts("All tests passed!")
IO.puts(String.duplicate("=", 60) <> "\n")
