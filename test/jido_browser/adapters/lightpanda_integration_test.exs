defmodule Jido.Browser.Adapters.LightpandaIntegrationTest do
  @moduledoc """
  Integration tests for the Lightpanda adapter against a local fixture server.

  Run with: mix test test/jido_browser/adapters/lightpanda_integration_test.exs --include integration
  Requires: Lightpanda binary installed (mix jido_browser.install lightpanda)
  """
  use ExUnit.Case, async: false

  alias Jido.Browser
  alias Jido.Browser.Adapters.Lightpanda
  alias Jido.Browser.Installer
  alias Jido.Browser.TestSupport.IntegrationTestServer

  @skip_reason (case Installer.bin_path(:lightpanda) do
                  path when is_binary(path) -> nil
                  nil -> "lightpanda integration unavailable: binary not found"
                end)

  @moduletag :integration
  @moduletag :lightpanda
  @moduletag timeout: 120_000
  if @skip_reason, do: @moduletag(skip: @skip_reason)

  @command_timeout 30_000

  setup_all do
    {:ok, server} = IntegrationTestServer.start()
    on_exit(fn -> IntegrationTestServer.stop(server) end)
    {:ok, base_url: IntegrationTestServer.base_url(server)}
  end

  setup do
    case Browser.start_session(adapter: Lightpanda, timeout: @command_timeout) do
      {:ok, session} ->
        on_exit(fn -> Browser.end_session(session) end)
        {:ok, session: session}

      {:error, reason} ->
        flunk("Failed to start Lightpanda integration session: #{inspect(reason)}")
    end
  end

  describe "base adapter operations" do
    test "navigates, extracts content, evaluates JavaScript, types, and screenshots", %{
      session: session,
      base_url: base_url
    } do
      {:ok, session, nav_result} = Browser.navigate(session, "#{base_url}/", timeout: @command_timeout)
      assert nav_result.url == "#{base_url}/"

      {:ok, session, title_result} = Browser.get_title(session, timeout: @command_timeout)
      assert title_result.title == "Integration Test Home"

      {:ok, session, content_result} =
        Browser.extract_content(session, selector: "body", format: :text, timeout: @command_timeout)

      assert content_result.format == :text
      assert content_result.content =~ "Integration Test Home"

      {:ok, session, eval_result} =
        Browser.evaluate(session, "document.querySelector('h1').textContent", timeout: @command_timeout)

      assert eval_result.result == "Integration Test Home"

      {:ok, session, type_result} =
        Browser.type(session, "#search-input", "lightpanda integration", timeout: @command_timeout)

      assert type_result.selector == "#search-input"

      {:ok, session, value_result} =
        Browser.evaluate(session, "document.querySelector('#search-input').value", timeout: @command_timeout)

      assert value_result.result == "lightpanda integration"

      {:ok, _session, screenshot_result} = Browser.screenshot(session, timeout: @command_timeout)
      assert screenshot_result.mime == "image/png"
      assert byte_size(screenshot_result.bytes) > 1000
    end
  end

  describe "warm pools" do
    test "checks out a prestarted Lightpanda CDP session", %{base_url: base_url} do
      pool_name = {:global, {:lightpanda_pool, System.unique_integer([:positive])}}
      assert {:ok, pool} = Browser.start_pool(adapter: Lightpanda, name: pool_name, size: 1)

      on_exit(fn -> Browser.stop_pool(pool) end)

      assert {:ok, session} = Browser.start_session(adapter: Lightpanda, pool: pool_name, checkout_timeout: 5_000)
      on_exit(fn -> Browser.end_session(session) end)

      assert {:ok, session, _nav_result} = Browser.navigate(session, "#{base_url}/article", timeout: @command_timeout)
      assert {:ok, _session, eval_result} = Browser.evaluate(session, "document.title", timeout: @command_timeout)
      assert eval_result.result == "Integration Test Article"
    end
  end
end
