defmodule JidoBrowser.Adapters.ContractTest do
  @moduledoc """
  Contract tests to verify adapter implementations match documented behavior.
  """
  use ExUnit.Case, async: true

  alias JidoBrowser.Adapters.Test, as: TestAdapter

  setup do
    {:ok, session} = TestAdapter.start_session([])
    {:ok, session, _} = TestAdapter.navigate(session, "https://example.com", [])
    {:ok, session: session}
  end

  describe "extract_content/2 format option" do
    test "returns format: :html when format: :html is passed", %{session: session} do
      {:ok, _session, result} = TestAdapter.extract_content(session, format: :html)

      assert result.format == :html
      assert result.content =~ "<h1>"
    end

    test "returns format: :text when format: :text is passed", %{session: session} do
      {:ok, _session, result} = TestAdapter.extract_content(session, format: :text)

      assert result.format == :text
      refute result.content =~ "<"
    end

    test "returns format: :markdown by default", %{session: session} do
      {:ok, _session, result} = TestAdapter.extract_content(session, [])

      assert result.format == :markdown
      assert result.content =~ "#"
    end
  end

  describe "screenshot/2 options" do
    test "accepts full_page option", %{session: session} do
      {:ok, _session, result} = TestAdapter.screenshot(session, full_page: true)

      assert result.format == :png
      assert result.mime == "image/png"
      assert is_binary(result.bytes)
    end

    test "returns format: :png by default", %{session: session} do
      {:ok, _session, result} = TestAdapter.screenshot(session, [])

      assert result.format == :png
      assert result.mime == "image/png"
    end

    test "returns error for unsupported format", %{session: session} do
      {:error, error} = TestAdapter.screenshot(session, format: :jpeg)

      assert error.details[:requested_format] == :jpeg
      assert error.details[:supported_formats] == [:png]
    end
  end

  describe "evaluate/3 returns structured data" do
    test "returns map when script returns object", %{session: session} do
      {:ok, _session, result} = TestAdapter.evaluate(session, "document.querySelector('div')", [])

      assert is_map(result.result)
      assert result.result["found"] == true
    end

    test "returns map for snapshot script", %{session: session} do
      {:ok, _session, result} = TestAdapter.evaluate(session, "snapshot()", [])

      assert is_map(result.result)
      assert result.result["url"] == "https://test.local"
      assert result.result["title"] == "Test Page"
      assert is_list(result.result["links"])
    end

    test "returns string for simple expressions", %{session: session} do
      {:ok, _session, result} = TestAdapter.evaluate(session, "document.title", [])

      assert result.result == "Test Page"
    end
  end
end
