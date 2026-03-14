defmodule Jido.Browser.Adapters.AgentBrowserIntegrationTest do
  @moduledoc """
  Advanced integration tests for the agent-browser backend against a local fixture server.

  Run with: mix test test/jido_browser/adapters/agent_browser_integration_test.exs --include integration
  Requires: agent-browser binary installed (mix jido_browser.install agent_browser)
  """

  use ExUnit.Case, async: false

  alias Jido.Browser
  alias Jido.Browser.Adapters.AgentBrowser
  alias Jido.Browser.AgentBrowser.Runtime
  alias Jido.Browser.TestSupport.IntegrationTestServer

  @skip_reason (case Runtime.find_binary() do
                  {:ok, binary} ->
                    case Runtime.ensure_supported_version(binary) do
                      :ok -> nil
                      {:error, reason} -> "agent-browser integration unavailable: #{inspect(reason)}"
                    end

                  {:error, reason} ->
                    "agent-browser integration unavailable: #{inspect(reason)}"
                end)

  @moduletag :integration
  @moduletag :agent_browser
  @moduletag timeout: 180_000
  if @skip_reason, do: @moduletag(skip: @skip_reason)

  @command_timeout 60_000

  setup_all do
    {:ok, server} = IntegrationTestServer.start()
    on_exit(fn -> IntegrationTestServer.stop(server) end)
    {:ok, base_url: IntegrationTestServer.base_url(server)}
  end

  setup do
    case Browser.start_session(adapter: AgentBrowser, headless: true, timeout: @command_timeout) do
      {:ok, session} ->
        on_exit(fn -> Browser.end_session(session) end)
        {:ok, session: session}

      {:error, reason} ->
        flunk("Failed to start agent-browser integration session: #{inspect(reason)}")
    end
  end

  describe "snapshot refs" do
    test "returns refs and allows ref-based type and click", %{session: session, base_url: base_url} do
      {:ok, session, _nav_result} = Browser.navigate(session, "#{base_url}/refs", timeout: @command_timeout)
      {:ok, session, snapshot_result} = Browser.snapshot(session, timeout: @command_timeout)

      snapshot_text = fetch_value(snapshot_result, :snapshot)
      refs = fetch_value(snapshot_result, :refs)

      assert is_binary(snapshot_text)
      assert is_map(refs)
      assert map_size(refs) > 0

      input_ref = ref_from_refs!(refs, "Ref Input Marker")
      button_ref = ref_from_refs!(refs, "Use Ref Button Marker")

      {:ok, session, _type_result} =
        Browser.type(session, input_ref, "from ref", clear: true, timeout: @command_timeout)

      {:ok, session, _click_result} = Browser.click(session, button_ref, timeout: @command_timeout)
      assert current_text!(session, "#ref-output") == "Submitted: from ref"
    end
  end

  describe "wait helpers" do
    test "waits for a delayed selector to appear", %{session: session, base_url: base_url} do
      {:ok, session, _nav_result} =
        Browser.navigate(session, "#{base_url}/dynamic", timeout: @command_timeout)

      {:ok, _session, result} =
        Browser.wait_for_selector(session, "#ready-message", state: :visible, timeout: 5_000)

      elapsed = fetch_value(result, :elapsed) || fetch_value(result, :elapsed_ms) || 0
      assert is_integer(elapsed)
      assert current_text!(session, "#ready-message") == "Dynamic content ready"
    end

    test "waits for a delayed navigation after click", %{session: session, base_url: base_url} do
      {:ok, session, _nav_result} =
        Browser.navigate(session, "#{base_url}/delayed-navigation", timeout: @command_timeout)

      {:ok, session, _click_result} = Browser.click(session, "#go-next", timeout: @command_timeout)

      {:ok, session, wait_result} =
        Browser.wait_for_navigation(session, url: "/next", timeout: 5_000)

      assert fetch_value(wait_result, :url) =~ "/next"

      {:ok, _session, title_result} = Browser.get_title(session, timeout: @command_timeout)
      assert fetch_value(title_result, :title) == "Integration Test Next"
    end
  end

  describe "session state" do
    test "saves state and restores it in a new session", %{session: session, base_url: base_url} do
      state_path =
        Path.join(System.tmp_dir!(), "agent_browser_state_#{System.unique_integer([:positive])}.json")

      on_exit(fn -> File.rm(state_path) end)

      {:ok, session, _nav_result} = Browser.navigate(session, "#{base_url}/state", timeout: @command_timeout)
      {:ok, session, _type_result} = Browser.type(session, "#state-name", "Ada", clear: true, timeout: @command_timeout)
      {:ok, _session, _click_result} = Browser.click(session, "#save-state", timeout: @command_timeout)

      assert current_text!(session, "#current-state") == "Ada"
      assert {:ok, _session, _save_result} = Browser.save_state(session, state_path, timeout: @command_timeout)

      {:ok, restored_session} =
        Browser.start_session(adapter: AgentBrowser, headless: true, timeout: @command_timeout)

      on_exit(fn -> Browser.end_session(restored_session) end)

      assert {:ok, restored_session, _load_result} =
               Browser.load_state(restored_session, state_path, timeout: @command_timeout)

      {:ok, restored_session, _nav_result} =
        Browser.navigate(restored_session, "#{base_url}/state", timeout: @command_timeout)

      assert current_text!(restored_session, "#current-state") == "Ada"
    end
  end

  describe "tab management" do
    test "opens, switches, lists, and closes tabs", %{session: session, base_url: base_url} do
      root_url = "#{base_url}/"
      article_url = "#{base_url}/article"

      {:ok, session, _nav_result} = Browser.navigate(session, root_url, timeout: @command_timeout)
      {:ok, session, _new_tab_result} = Browser.new_tab(session, article_url, timeout: @command_timeout)

      {:ok, _session, tabs_result} = Browser.list_tabs(session, timeout: @command_timeout)
      assert length(tab_entries(tabs_result)) >= 2

      {:ok, session, _switch_result} = Browser.switch_tab(session, 0, timeout: @command_timeout)
      {:ok, _session, url_result} = Browser.get_url(session, timeout: @command_timeout)
      assert fetch_value(url_result, :url) == root_url

      {:ok, session, _switch_result} = Browser.switch_tab(session, 1, timeout: @command_timeout)
      {:ok, _session, article_result} = Browser.get_url(session, timeout: @command_timeout)
      assert fetch_value(article_result, :url) == article_url

      {:ok, session, _close_result} = Browser.close_tab(session, 1, timeout: @command_timeout)
      {:ok, _session, remaining_tabs_result} = Browser.list_tabs(session, timeout: @command_timeout)
      assert length(tab_entries(remaining_tabs_result)) == 1
    end
  end

  describe "diagnostics" do
    test "collects console output", %{session: session, base_url: base_url} do
      {:ok, session, _nav_result} =
        Browser.navigate(session, "#{base_url}/console-and-errors", timeout: @command_timeout)

      Process.sleep(750)

      {:ok, _session, result} = Browser.console(session, timeout: @command_timeout)
      assert serialized(result) =~ "fixture-console-ready"
    end

    test "collects browser errors", %{session: session, base_url: base_url} do
      {:ok, session, _nav_result} =
        Browser.navigate(session, "#{base_url}/console-and-errors", timeout: @command_timeout)

      Process.sleep(750)

      {:ok, _session, result} = Browser.errors(session, timeout: @command_timeout)
      serialized = serialized(result)

      assert serialized =~ "fixture-page-error" or serialized =~ "fixture-console-error"
    end
  end

  describe "element queries" do
    test "returns a stable query result shape with elements and count", %{session: session, base_url: base_url} do
      {:ok, session, _nav_result} = Browser.navigate(session, "#{base_url}/", timeout: @command_timeout)

      {:ok, _session, result} = Browser.query(session, "a", limit: 1, timeout: @command_timeout)

      assert fetch_value(result, :count) == 1

      assert [
               %{
                 "tag" => "a",
                 "text" => "Next Page"
               }
             ] = fetch_value(result, :elements)
    end

    test "gets element attributes through the native adapter", %{session: session, base_url: base_url} do
      {:ok, session, _nav_result} =
        Browser.navigate(session, "#{base_url}/article", timeout: @command_timeout)

      {:ok, _session, result} =
        Browser.get_attribute(session, "article", "data-testid", timeout: @command_timeout)

      assert fetch_value(result, :value) == "fixture-article"
    end
  end

  describe "content extraction" do
    test "extracts markdown, html, and text", %{session: session, base_url: base_url} do
      {:ok, session, _nav_result} =
        Browser.navigate(session, "#{base_url}/article", timeout: @command_timeout)

      {:ok, _session, markdown_result} =
        Browser.extract_content(session, format: :markdown, timeout: @command_timeout)

      {:ok, _session, page_text_result} =
        Browser.extract_content(session, format: :text, timeout: @command_timeout)

      {:ok, _session, html_result} =
        Browser.extract_content(session, selector: "article", format: :html, timeout: @command_timeout)

      {:ok, _session, text_result} =
        Browser.extract_content(session, selector: "article", format: :text, timeout: @command_timeout)

      assert fetch_value(markdown_result, :content) =~ "Deterministic Fixture Content"
      assert fetch_value(page_text_result, :content) =~ "Deterministic Fixture Content"
      assert fetch_value(html_result, :content) =~ ~s(<article data-testid="fixture-article">)
      assert fetch_value(text_result, :content) =~ "Deterministic Fixture Content"
    end
  end

  defp current_text!(session, selector) do
    {:ok, _session, result} = Browser.get_text(session, selector, timeout: @command_timeout)
    fetch_value(result, :text)
  end

  defp ref_from_refs!(refs, marker) when is_map(refs) do
    refs
    |> Enum.find_value(fn {ref, entry} ->
      name = fetch_value(entry, :name)

      if is_binary(name) and String.contains?(String.downcase(name), String.downcase(marker)) do
        normalize_ref(ref)
      end
    end)
    |> case do
      nil -> flunk("Could not find ref for #{inspect(marker)} in refs:\n#{inspect(refs, pretty: true)}")
      ref -> ref
    end
  end

  defp normalize_ref("@" <> _ = ref), do: ref
  defp normalize_ref(ref), do: "@#{ref}"

  defp tab_entries(result) when is_list(result), do: result

  defp tab_entries(result) when is_map(result) do
    fetch_value(result, :tabs) ||
      fetch_value(result, :pages) ||
      fetch_value(result, :items) ||
      []
  end

  defp fetch_value(map, key) when is_map(map) and is_atom(key) do
    case Map.fetch(map, key) do
      {:ok, value} -> value
      :error -> Map.get(map, Atom.to_string(key))
    end
  end

  defp serialized(result), do: inspect(result, pretty: true, limit: :infinity)
end
