defmodule Jido.Browser.ResultTest do
  use ExUnit.Case, async: true

  alias Jido.Browser.Result
  alias Jido.Browser.Session

  defmodule FallbackAdapter do
    def evaluate(session, script, _opts) do
      result =
        cond do
          String.contains?(script, "querySelectorAll") ->
            [%{"index" => 0, "tag" => "a", "text" => "Example"}]

          String.contains?(script, "snapshot") ->
            %{
              "url" => "https://example.com",
              "title" => "Example",
              "snapshot" => "Example content",
              "refs" => %{"@e1" => %{"role" => "link", "text" => "Example"}}
            }

          true ->
            %{"hovered" => true, "selector" => "#target"}
        end

      {:ok, session, %{result: result}}
    end
  end

  test "normalizes known public fields without creating runtime atoms" do
    assert Result.normalize(%{
             "url" => "https://example.com",
             "tabId" => "tab-1",
             "unknownProtocolField" => 42
           }) == %{
             url: "https://example.com",
             tab_id: "tab-1",
             raw: %{"unknownProtocolField" => 42}
           }
  end

  test "normalizes nested public fields and keeps dynamic ref identifiers" do
    assert Result.normalize(%{
             "refs" => %{
               "@e1" => %{"role" => "link", "text" => "Home"}
             },
             "tabs" => [%{"tabId" => "tab-1", "url" => "https://example.com"}]
           }) == %{
             refs: %{"@e1" => %{role: "link", text: "Home"}},
             tabs: [%{tab_id: "tab-1", url: "https://example.com"}]
           }
  end

  test "keeps evaluation, metadata, and raw payloads opaque" do
    assert Result.normalize(%{
             "result" => %{"answer" => 42},
             metadata: %{"author" => "Jido"},
             raw: %{"wire" => true}
           }) == %{
             result: %{"answer" => 42},
             metadata: %{"author" => "Jido"},
             raw: %{"wire" => true}
           }
  end

  test "preserves atom fields from native Elixir adapters" do
    assert Result.normalize(%{url: "https://example.com", selector: "main"}) == %{
             url: "https://example.com",
             selector: "main"
           }
  end

  test "normalizes generated JavaScript fallback and composite results" do
    session = %Session{id: "result-contract", adapter: FallbackAdapter, started_at: DateTime.utc_now()}

    assert {:ok, ^session, snapshot} = Jido.Browser.snapshot(session)
    assert snapshot.url == "https://example.com"
    assert snapshot.refs["@e1"] == %{role: "link", text: "Example"}

    assert {:ok, ^session, %{hovered: true, selector: "#target"}} =
             Jido.Browser.hover(session, "#target")

    assert {:ok, ^session, %{count: 1, elements: [%{index: 0, tag: "a", text: "Example"}]}} =
             Jido.Browser.query(session, "a", limit: 1)
  end
end
