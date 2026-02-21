defmodule JidoBrowser.Adapters.WebIntegrationTest do
  @moduledoc """
  Integration tests for the Web adapter against a local fixture server.

  Run with: mix test --include integration
  """
  use ExUnit.Case, async: false

  alias JidoBrowser.Adapters.Web
  alias JidoBrowser.TestSupport.IntegrationTestServer

  @moduletag :integration

  setup_all do
    {:ok, server} = IntegrationTestServer.start()
    on_exit(fn -> IntegrationTestServer.stop(server) end)
    {:ok, base_url: IntegrationTestServer.base_url(server)}
  end

  setup do
    case Web.start_session() do
      {:ok, session} ->
        on_exit(fn -> Web.end_session(session) end)
        {:ok, session: session}

      {:error, reason} ->
        flunk("Failed to start Web integration session: #{inspect(reason)}")
    end
  end

  describe "navigate/3" do
    test "fetches local fixture webpage and returns markdown content", %{
      session: session,
      base_url: base_url
    } do
      url = "#{base_url}/"
      {:ok, _session, result} = Web.navigate(session, url, [])

      assert result.url == url
      assert is_binary(result.content)
      assert result.content =~ "Integration Test Home"
    end

    test "navigates to a second local page", %{session: session, base_url: base_url} do
      url = "#{base_url}/article"
      {:ok, _session, result} = Web.navigate(session, url, [])

      assert result.url == url
      assert is_binary(result.content)
      assert result.content =~ "Deterministic Fixture Content"
    end
  end

  describe "extract_content/2" do
    test "extracts content as markdown", %{session: session, base_url: base_url} do
      {:ok, session, _nav_result} = Web.navigate(session, "#{base_url}/article", [])
      {:ok, _session, result} = Web.extract_content(session, [])

      assert result.format == :markdown
      assert is_binary(result.content)
      assert result.content =~ "Deterministic Fixture Content"
    end
  end

  describe "error handling" do
    test "returns error for invalid URL", %{session: session} do
      invalid_url = IntegrationTestServer.unreachable_url()
      result = Web.navigate(session, invalid_url, [])

      assert {:error, _} = result
    end
  end
end
