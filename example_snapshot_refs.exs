# Run with: mix run example_snapshot_refs.exs

alias Jido.Browser

{:ok, session} = Browser.start_session()

try do
  {:ok, session, _nav_result} = Browser.navigate(session, "https://example.com")
  {:ok, session, snapshot_result} = Browser.snapshot(session)

  snapshot = snapshot_result["snapshot"] || snapshot_result[:snapshot] || ""

  IO.puts("Snapshot:")
  IO.puts(snapshot)

  first_ref =
    snapshot
    |> String.split("\n")
    |> Enum.find_value(fn line ->
      case Regex.run(~r/@e\d+/, line) do
        [ref] -> ref
        _ -> nil
      end
    end)

  case first_ref do
    nil ->
      IO.puts("No interactive refs were found in the snapshot.")

    ref ->
      IO.puts("Clicking #{ref}")
      {:ok, session, _click_result} = Browser.click(session, ref)
      {:ok, _session, title_result} = Browser.get_title(session)
      IO.puts("Current title: #{title_result["title"] || title_result[:title]}")
  end
after
  Browser.end_session(session)
end
