defmodule JidoBrowser.Adapters.VibiumIntegrationTest do
  @moduledoc """
  Integration tests for the Vibium adapter against real websites.

  Run with: mix test --only integration
  Requires: vibium binary installed (mix jido_browser.install vibium)
  """
  use ExUnit.Case, async: false

  alias JidoBrowser.Adapters.Vibium

  @moduletag :integration

  setup do
    case Vibium.start_session(headless: true) do
      {:ok, session} ->
        on_exit(fn -> Vibium.end_session(session) end)
        {:ok, session: session}

      {:error, reason} ->
        flunk("Failed to start Vibium integration session: #{inspect(reason)}")
    end
  end

  describe "navigate/3" do
    test "fetches a real webpage", %{session: session} do
      {:ok, _session, result} = Vibium.navigate(session, "https://example.com", [])
      assert result.url == "https://example.com"
    end

    test "handles HTTPS sites", %{session: session} do
      {:ok, _session, result} = Vibium.navigate(session, "https://httpbin.org/html", [])
      assert result.url == "https://httpbin.org/html"
    end
  end

  describe "click/3" do
    test "clicks an element on the page", %{session: session} do
      {:ok, session, _nav_result} = Vibium.navigate(session, "https://example.com", [])
      {:ok, _session, result} = Vibium.click(session, "a", [])
      assert %{selector: "a"} = result
    end
  end

  describe "screenshot/2" do
    test "captures a screenshot", %{session: session} do
      {:ok, session, _nav_result} = Vibium.navigate(session, "https://example.com", [])
      {:ok, _session, result} = Vibium.screenshot(session, [])

      assert result.mime == "image/png"
      assert is_binary(result.bytes)
      assert byte_size(result.bytes) > 1000
    end
  end

  describe "extract_content/2" do
    test "extracts page content", %{session: session} do
      {:ok, session, _nav_result} = Vibium.navigate(session, "https://example.com", [])
      {:ok, _session, result} = Vibium.extract_content(session, [])

      assert is_binary(result.content)
    end
  end

  describe "type/4" do
    test "types text into a search input", %{session: session} do
      {:ok, session, _nav_result} = Vibium.navigate(session, "https://duckduckgo.com", [])
      {:ok, _session, result} = Vibium.type(session, "input[name='q']", "elixir lang", [])
      assert %{selector: "input[name='q']"} = result
    end
  end

  describe "error handling" do
    test "returns error for invalid URL", %{session: session} do
      result =
        Vibium.navigate(
          session,
          "https://this-domain-definitely-does-not-exist-12345.com",
          []
        )

      assert {:error, _} = result
    end
  end
end
