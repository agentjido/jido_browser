defmodule Jido.Browser.PluginTest do
  use ExUnit.Case, async: true

  alias Jido.Browser.Plugin

  describe "plugin metadata" do
    test "has correct name" do
      assert Plugin.name() == "browser"
    end

    test "has correct state_key" do
      assert Plugin.state_key() == :browser
    end

    test "has correct category" do
      assert Plugin.category() == "browser"
    end

    test "has expected tags" do
      tags = Plugin.tags()
      assert "browser" in tags
      assert "web" in tags
      assert "automation" in tags
    end

    test "has 38 actions" do
      actions = Plugin.actions()
      assert length(actions) == 38
    end

    test "includes all expected action modules" do
      actions = Plugin.actions()

      # Session lifecycle
      assert Jido.Browser.Actions.StartSession in actions
      assert Jido.Browser.Actions.EndSession in actions
      assert Jido.Browser.Actions.GetStatus in actions
      assert Jido.Browser.Actions.SaveState in actions
      assert Jido.Browser.Actions.LoadState in actions

      # Navigation
      assert Jido.Browser.Actions.Navigate in actions
      assert Jido.Browser.Actions.Back in actions
      assert Jido.Browser.Actions.Forward in actions
      assert Jido.Browser.Actions.Reload in actions

      # Interaction
      assert Jido.Browser.Actions.Click in actions
      assert Jido.Browser.Actions.Type in actions
      assert Jido.Browser.Actions.Hover in actions
      assert Jido.Browser.Actions.Scroll in actions

      # Waiting
      assert Jido.Browser.Actions.Wait in actions
      assert Jido.Browser.Actions.WaitForSelector in actions
      assert Jido.Browser.Actions.WaitForNavigation in actions

      # Queries
      assert Jido.Browser.Actions.Query in actions
      assert Jido.Browser.Actions.GetText in actions
      assert Jido.Browser.Actions.IsVisible in actions
      assert Jido.Browser.Actions.ListTabs in actions
      assert Jido.Browser.Actions.NewTab in actions
      assert Jido.Browser.Actions.SwitchTab in actions
      assert Jido.Browser.Actions.CloseTab in actions

      # Extraction
      assert Jido.Browser.Actions.Snapshot in actions
      assert Jido.Browser.Actions.Screenshot in actions
      assert Jido.Browser.Actions.ExtractContent in actions
      assert Jido.Browser.Actions.Console in actions
      assert Jido.Browser.Actions.Errors in actions

      # Advanced
      assert Jido.Browser.Actions.Evaluate in actions
      assert Jido.Browser.Actions.WebFetch in actions
    end
  end

  describe "signal_routes/1" do
    test "returns 38 routes" do
      routes = Plugin.signal_routes(%{})
      assert length(routes) == 38
    end

    test "maps browser.navigate to Navigate action" do
      routes = Plugin.signal_routes(%{})
      assert {"browser.navigate", Jido.Browser.Actions.Navigate} in routes
    end

    test "maps browser.snapshot to Snapshot action" do
      routes = Plugin.signal_routes(%{})
      assert {"browser.snapshot", Jido.Browser.Actions.Snapshot} in routes
    end

    test "maps browser.click to Click action" do
      routes = Plugin.signal_routes(%{})
      assert {"browser.click", Jido.Browser.Actions.Click} in routes
    end

    test "all routes have browser. prefix" do
      routes = Plugin.signal_routes(%{})

      for {pattern, _action} <- routes do
        assert String.starts_with?(pattern, "browser.")
      end
    end
  end

  describe "mount/2" do
    test "returns ok tuple with initial state" do
      assert {:ok, state} = Plugin.mount(%{}, %{})
      assert is_map(state)
    end

    test "initializes with default values" do
      {:ok, state} = Plugin.mount(%{}, %{})

      assert state.session == nil
      assert state.headless == true
      assert state.timeout == 30_000
      assert state.viewport == %{width: 1280, height: 720}
      assert state.adapter == Jido.Browser.Adapters.AgentBrowser
      assert state.pool == nil
      assert state.checkout_timeout == 5_000
      assert state.last_url == nil
      assert state.last_title == nil
      assert state.seen_urls == []
      assert state.web_fetch_uses == 0
    end

    test "accepts headless config override" do
      {:ok, state} = Plugin.mount(%{}, %{headless: false})
      assert state.headless == false
    end

    test "accepts timeout config override" do
      {:ok, state} = Plugin.mount(%{}, %{timeout: 60_000})
      assert state.timeout == 60_000
    end

    test "accepts viewport config override" do
      {:ok, state} = Plugin.mount(%{}, %{viewport: %{width: 1920, height: 1080}})
      assert state.viewport == %{width: 1920, height: 1080}
    end

    test "accepts base_url config" do
      {:ok, state} = Plugin.mount(%{}, %{base_url: "https://example.com"})
      assert state.base_url == "https://example.com"
    end

    test "accepts adapter config" do
      {:ok, state} = Plugin.mount(%{}, %{adapter: Jido.Browser.Adapters.Web})
      assert state.adapter == Jido.Browser.Adapters.Web
    end

    test "accepts pool config overrides" do
      {:ok, state} = Plugin.mount(%{}, %{pool: "warm", checkout_timeout: 9_000})
      assert state.pool == "warm"
      assert state.checkout_timeout == 9_000
    end
  end

  describe "signal_patterns/0" do
    test "returns list of signal patterns" do
      patterns = Plugin.signal_patterns()
      assert is_list(patterns)
      assert length(patterns) == 38
    end

    test "all patterns have browser. prefix" do
      for pattern <- Plugin.signal_patterns() do
        assert String.starts_with?(pattern, "browser.")
      end
    end

    test "includes expected patterns" do
      patterns = Plugin.signal_patterns()

      assert "browser.navigate" in patterns
      assert "browser.click" in patterns
      assert "browser.snapshot" in patterns
      assert "browser.wait_for_selector" in patterns
      assert "browser.save_state" in patterns
      assert "browser.tab_list" in patterns
      assert "browser.console" in patterns
      assert "browser.web_fetch" in patterns
    end
  end

  describe "handle_signal/2" do
    test "returns continue" do
      assert {:ok, :continue} = Plugin.handle_signal(%{}, %{})
    end
  end

  describe "transform_result/3" do
    test "passes through successful results" do
      result = {:ok, %{status: "success"}}
      assert Plugin.transform_result(:some_action, result, %{}) == result
    end

    test "tracks discovered URLs and fetch usage for web fetch results" do
      context = %{skill_state: %{seen_urls: ["https://seed.example"], web_fetch_uses: 1}}

      result =
        Plugin.transform_result(
          Jido.Browser.Actions.WebFetch,
          {:ok, %{url: "https://example.com", final_url: "https://example.com/final", status: "success"}},
          context
        )

      assert {:ok, _result, state_updates} = result

      assert Enum.sort(state_updates.seen_urls) ==
               Enum.sort(["https://seed.example", "https://example.com", "https://example.com/final"])

      assert state_updates.web_fetch_uses == 2
    end

    test "tracks URLs returned by search results" do
      result =
        Plugin.transform_result(
          Jido.Browser.Actions.SearchWeb,
          {:ok, %{results: [%{url: "https://elixir-lang.org"}]}},
          %{skill_state: %{}}
        )

      assert {:ok, _result, state_updates} = result
      assert state_updates.seen_urls == ["https://elixir-lang.org"]
    end

    test "enhances error results when session available" do
      context = %{
        skill_state: %{
          session: %{},
          last_url: "https://example.com",
          last_title: "Test Page"
        }
      }

      error_result = {:error, %{message: "Element not found"}}
      result = Plugin.transform_result(:click, error_result, context)

      assert {:error, enhanced} = result
      assert enhanced.diagnostics.url == "https://example.com"
      assert enhanced.diagnostics.title == "Test Page"
    end
  end
end
