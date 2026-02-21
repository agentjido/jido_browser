defmodule JidoBrowser.Adapters.VibiumIntegrationTest do
  @moduledoc """
  Integration tests for the Vibium adapter against a local fixture server.

  Run with: mix test --include integration
  Requires: vibium binary installed (mix jido_browser.install vibium)
  """
  use ExUnit.Case, async: false

  alias JidoBrowser.Adapters.Vibium
  alias JidoBrowser.TestSupport.IntegrationTestServer

  @moduletag :integration

  setup_all do
    {:ok, server} = IntegrationTestServer.start()
    on_exit(fn -> IntegrationTestServer.stop(server) end)
    {:ok, base_url: IntegrationTestServer.base_url(server)}
  end

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
    test "fetches local fixture webpage", %{session: session, base_url: base_url} do
      url = "#{base_url}/"
      {:ok, _session, result} = Vibium.navigate(session, url, [])
      assert result.url == url
    end

    test "navigates to a second local page", %{session: session, base_url: base_url} do
      url = "#{base_url}/article"
      {:ok, _session, result} = Vibium.navigate(session, url, [])
      assert result.url == url
    end
  end

  describe "click/3" do
    test "clicks an element on the page", %{session: session, base_url: base_url} do
      {:ok, session, _nav_result} = Vibium.navigate(session, "#{base_url}/", [])
      {:ok, _session, result} = Vibium.click(session, "a#next-link", [])
      assert %{selector: "a#next-link"} = result
    end
  end

  describe "screenshot/2" do
    test "captures a screenshot", %{session: session, base_url: base_url} do
      {:ok, session, _nav_result} = Vibium.navigate(session, "#{base_url}/", [])
      {:ok, _session, result} = Vibium.screenshot(session, [])

      assert result.mime == "image/png"
      assert is_binary(result.bytes)
      assert byte_size(result.bytes) > 1000
    end
  end

  describe "extract_content/2" do
    test "extracts page content", %{session: session, base_url: base_url} do
      {:ok, session, _nav_result} = Vibium.navigate(session, "#{base_url}/article", [])
      {:ok, _session, result} = Vibium.extract_content(session, [])

      assert is_binary(result.content)
    end
  end

  describe "type/4" do
    test "types text into a search input", %{session: session, base_url: base_url} do
      {:ok, session, _nav_result} = Vibium.navigate(session, "#{base_url}/", [])
      {:ok, _session, result} = Vibium.type(session, "input[name='q']", "elixir lang", [])
      assert %{selector: "input[name='q']"} = result
    end
  end

  describe "error handling" do
    test "returns error for invalid URL", %{session: session} do
      invalid_url = IntegrationTestServer.unreachable_url()
      result = Vibium.navigate(session, invalid_url, [])

      assert {:error, _} = result
    end
  end
end
