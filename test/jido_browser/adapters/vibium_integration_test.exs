defmodule Jido.Browser.Adapters.VibiumIntegrationTest do
  @moduledoc """
  Integration tests for the Vibium adapter against a local fixture server.

  Run with: mix test --include integration
  Requires: vibium binary installed (mix jido_browser.install vibium)
  """
  use ExUnit.Case, async: false

  alias Jido.Browser.Adapters.Vibium
  alias Jido.Browser.TestSupport.IntegrationTestServer

  @moduletag :integration
  @moduletag timeout: 120_000
  @command_timeout 60_000

  setup_all do
    {:ok, server} = IntegrationTestServer.start()
    base_url = IntegrationTestServer.base_url(server)

    case Vibium.start_session(headless: true) do
      {:ok, session} ->
        on_exit(fn ->
          Vibium.end_session(session)
          IntegrationTestServer.stop(server)
        end)

        {:ok, session: session, base_url: base_url}

      {:error, reason} ->
        flunk("Failed to start Vibium integration session: #{inspect(reason)}")
    end
  end

  describe "navigate/3" do
    test "fetches local fixture webpage", %{session: session, base_url: base_url} do
      url = "#{base_url}/"
      {:ok, _session, result} = Vibium.navigate(session, url, timeout: @command_timeout)
      assert result.url == url
    end

    test "navigates to a second local page", %{session: session, base_url: base_url} do
      url = "#{base_url}/article"
      {:ok, _session, result} = Vibium.navigate(session, url, timeout: @command_timeout)
      assert result.url == url
    end
  end

  describe "click/3" do
    test "clicks an element on the page", %{session: session, base_url: base_url} do
      {:ok, session, _nav_result} = Vibium.navigate(session, "#{base_url}/", timeout: @command_timeout)
      {:ok, _session, result} = Vibium.click(session, "a#next-link", timeout: @command_timeout)
      assert %{selector: "a#next-link"} = result
    end
  end

  describe "screenshot/2" do
    test "captures a screenshot", %{session: session, base_url: base_url} do
      {:ok, session, _nav_result} = Vibium.navigate(session, "#{base_url}/", timeout: @command_timeout)
      {:ok, _session, result} = Vibium.screenshot(session, timeout: @command_timeout)

      assert result.mime == "image/png"
      assert is_binary(result.bytes)
      assert byte_size(result.bytes) > 1000
    end
  end

  describe "extract_content/2" do
    test "extracts page content", %{session: session, base_url: base_url} do
      {:ok, session, _nav_result} =
        Vibium.navigate(session, "#{base_url}/article", timeout: @command_timeout)

      {:ok, _session, result} = Vibium.extract_content(session, timeout: @command_timeout)

      assert is_binary(result.content)
    end
  end

  describe "type/4" do
    test "types text into a search input", %{session: session, base_url: base_url} do
      {:ok, session, _nav_result} = Vibium.navigate(session, "#{base_url}/", timeout: @command_timeout)

      {:ok, _session, result} =
        Vibium.type(session, "input[name='q']", "elixir lang", timeout: @command_timeout)

      assert %{selector: "input[name='q']"} = result
    end
  end

  describe "error handling" do
    test "returns error for invalid URL", %{session: session} do
      invalid_url = IntegrationTestServer.unreachable_url()
      result = Vibium.navigate(session, invalid_url, timeout: @command_timeout)

      assert {:error, _} = result
    end
  end
end
