defmodule Jido.Browser.Adapters.WebIntegrationTest do
  @moduledoc """
  Integration tests for the Web adapter against a local fixture server.

  Run with: mix test --include integration
  """
  use ExUnit.Case, async: false

  alias Jido.Browser
  alias Jido.Browser.Adapters.Web
  alias Jido.Browser.Adapters.Web.CLI
  alias Jido.Browser.TestSupport.IntegrationTestServer

  @moduletag :integration

  setup_all do
    {:ok, server} = IntegrationTestServer.start()
    on_exit(fn -> IntegrationTestServer.stop(server) end)
    base_url = IntegrationTestServer.base_url(server)

    context =
      case web_integration_skip_reason(base_url) do
        nil -> [base_url: base_url]
        reason -> [base_url: base_url, skip: reason]
      end

    {:ok, context}
  end

  setup do
    profile = "web-integration-#{System.unique_integer([:positive])}"

    case Web.start_session(profile: profile) do
      {:ok, session} ->
        on_exit(fn ->
          Web.end_session(session)
          CLI.delete_profile(profile)
        end)

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

  describe "warm pooled sessions" do
    test "uses a supervised warm pool against the local fixture server", %{base_url: base_url} do
      pool_name = {:global, {:web_pool, System.unique_integer([:positive])}}

      assert {:ok, pool} = Browser.start_pool(adapter: Web, name: pool_name, size: 1)

      on_exit(fn -> Browser.stop_pool(pool) end)

      assert {:ok, session} = Browser.start_session(adapter: Web, pool: pool_name, checkout_timeout: 5_000)
      on_exit(fn -> Browser.end_session(session) end)

      {:ok, session, result} = Web.navigate(session, "#{base_url}/article", [])
      assert result.url == "#{base_url}/article"
      assert result.content =~ "Deterministic Fixture Content"

      assert {:ok, _session, extracted} = Web.extract_content(session, format: :text)
      assert extracted.content =~ "Deterministic Fixture Content"
    end
  end

  describe "error handling" do
    test "returns error for invalid URL", %{session: session} do
      invalid_url = IntegrationTestServer.unreachable_url()
      result = Web.navigate(session, invalid_url, [])

      assert {:error, _} = result
    end
  end

  defp web_integration_skip_reason(base_url) do
    profile = "web-integration-smoke-#{System.unique_integer([:positive])}"

    result =
      with {:ok, session} <- Web.start_session(profile: profile),
           {:ok, _session, _result} <- Web.navigate(session, "#{base_url}/", []) do
        nil
      else
        {:error, reason} -> "web integration unavailable: #{inspect(reason)}"
      end

    CLI.delete_profile(profile)
    result
  end
end
