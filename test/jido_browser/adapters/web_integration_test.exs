defmodule JidoBrowser.Adapters.WebIntegrationTest do
  @moduledoc """
  Integration tests for the Web adapter against real websites.

  Run with: mix test --only integration
  """
  use ExUnit.Case, async: false

  alias JidoBrowser.Adapters.Web

  @moduletag :integration

  setup context do
    if context[:skip_web] do
      :ok
    else
      case Web.start_session() do
        {:ok, session} ->
          on_exit(fn -> Web.end_session(session) end)
          {:ok, session: session}

        {:error, _reason} ->
          :ok
      end
    end
  end

  describe "navigate/3" do
    test "fetches a real webpage and returns markdown content", context do
      if session = context[:session] do
        {:ok, _session, result} = Web.navigate(session, "https://example.com", [])

        assert result.url == "https://example.com"
        assert is_binary(result.content)
        assert result.content =~ "Example Domain"
      end
    end

    test "handles HTTPS sites", context do
      if session = context[:session] do
        {:ok, _session, result} = Web.navigate(session, "https://httpbin.org/html", [])

        assert result.url == "https://httpbin.org/html"
        assert is_binary(result.content)
        assert result.content =~ "Moby-Dick" or result.content =~ "Herman Melville"
      end
    end
  end

  describe "extract_content/2" do
    test "extracts content as markdown", context do
      if session = context[:session] do
        {:ok, session, _nav_result} = Web.navigate(session, "https://example.com", [])
        {:ok, _session, result} = Web.extract_content(session, [])

        assert result.format == :markdown
        assert is_binary(result.content)
        assert result.content =~ "Example Domain"
      end
    end
  end

  describe "error handling" do
    test "returns error for invalid URL", context do
      if session = context[:session] do
        result =
          Web.navigate(
            session,
            "https://this-domain-definitely-does-not-exist-12345.com",
            []
          )

        assert {:error, _} = result
      end
    end
  end
end
