defmodule Jido.Browser.ResultTest do
  use ExUnit.Case, async: true

  alias Jido.Browser.Result

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
end
