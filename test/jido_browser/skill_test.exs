defmodule JidoBrowser.SkillTest do
  use ExUnit.Case, async: true

  alias JidoBrowser.Skill

  describe "skill metadata" do
    test "has correct name" do
      assert Skill.name() == "browser"
    end

    test "has correct state_key" do
      assert Skill.state_key() == :browser
    end

    test "has correct category" do
      assert Skill.category() == "browser"
    end

    test "has expected tags" do
      tags = Skill.tags()
      assert "browser" in tags
      assert "web" in tags
      assert "automation" in tags
    end

    test "has 26 actions" do
      actions = Skill.actions()
      assert length(actions) == 26
    end

    test "includes all expected action modules" do
      actions = Skill.actions()

      # Session lifecycle
      assert JidoBrowser.Actions.StartSession in actions
      assert JidoBrowser.Actions.EndSession in actions
      assert JidoBrowser.Actions.GetStatus in actions

      # Navigation
      assert JidoBrowser.Actions.Navigate in actions
      assert JidoBrowser.Actions.Back in actions
      assert JidoBrowser.Actions.Forward in actions
      assert JidoBrowser.Actions.Reload in actions

      # Interaction
      assert JidoBrowser.Actions.Click in actions
      assert JidoBrowser.Actions.Type in actions
      assert JidoBrowser.Actions.Hover in actions
      assert JidoBrowser.Actions.Scroll in actions

      # Waiting
      assert JidoBrowser.Actions.Wait in actions
      assert JidoBrowser.Actions.WaitForSelector in actions
      assert JidoBrowser.Actions.WaitForNavigation in actions

      # Queries
      assert JidoBrowser.Actions.Query in actions
      assert JidoBrowser.Actions.GetText in actions
      assert JidoBrowser.Actions.IsVisible in actions

      # Extraction
      assert JidoBrowser.Actions.Snapshot in actions
      assert JidoBrowser.Actions.Screenshot in actions
      assert JidoBrowser.Actions.ExtractContent in actions

      # Advanced
      assert JidoBrowser.Actions.Evaluate in actions
    end
  end

  describe "router/1" do
    test "returns 26 routes" do
      routes = Skill.router(%{})
      assert length(routes) == 26
    end

    test "maps browser.navigate to Navigate action" do
      routes = Skill.router(%{})
      assert {"browser.navigate", JidoBrowser.Actions.Navigate} in routes
    end

    test "maps browser.snapshot to Snapshot action" do
      routes = Skill.router(%{})
      assert {"browser.snapshot", JidoBrowser.Actions.Snapshot} in routes
    end

    test "maps browser.click to Click action" do
      routes = Skill.router(%{})
      assert {"browser.click", JidoBrowser.Actions.Click} in routes
    end

    test "all routes have browser. prefix" do
      routes = Skill.router(%{})

      for {pattern, _action} <- routes do
        assert String.starts_with?(pattern, "browser.")
      end
    end
  end

  describe "mount/2" do
    test "returns ok tuple with initial state" do
      assert {:ok, state} = Skill.mount(%{}, %{})
      assert is_map(state)
    end

    test "initializes with default values" do
      {:ok, state} = Skill.mount(%{}, %{})

      assert state.session == nil
      assert state.headless == true
      assert state.timeout == 30_000
      assert state.viewport == %{width: 1280, height: 720}
      assert state.last_url == nil
      assert state.last_title == nil
    end

    test "accepts headless config override" do
      {:ok, state} = Skill.mount(%{}, %{headless: false})
      assert state.headless == false
    end

    test "accepts timeout config override" do
      {:ok, state} = Skill.mount(%{}, %{timeout: 60_000})
      assert state.timeout == 60_000
    end

    test "accepts viewport config override" do
      {:ok, state} = Skill.mount(%{}, %{viewport: %{width: 1920, height: 1080}})
      assert state.viewport == %{width: 1920, height: 1080}
    end

    test "accepts base_url config" do
      {:ok, state} = Skill.mount(%{}, %{base_url: "https://example.com"})
      assert state.base_url == "https://example.com"
    end

    test "accepts adapter config" do
      {:ok, state} = Skill.mount(%{}, %{adapter: JidoBrowser.Adapters.Web})
      assert state.adapter == JidoBrowser.Adapters.Web
    end
  end

  describe "signal_patterns/0" do
    test "returns list of signal patterns" do
      patterns = Skill.signal_patterns()
      assert is_list(patterns)
      assert length(patterns) == 26
    end

    test "all patterns have browser. prefix" do
      for pattern <- Skill.signal_patterns() do
        assert String.starts_with?(pattern, "browser.")
      end
    end

    test "includes expected patterns" do
      patterns = Skill.signal_patterns()

      assert "browser.navigate" in patterns
      assert "browser.click" in patterns
      assert "browser.snapshot" in patterns
      assert "browser.wait_for_selector" in patterns
    end
  end

  describe "handle_signal/2" do
    test "returns continue" do
      assert {:ok, :continue} = Skill.handle_signal(%{}, %{})
    end
  end

  describe "transform_result/3" do
    test "passes through successful results" do
      result = {:ok, %{status: "success"}}
      assert Skill.transform_result(:some_action, result, %{}) == result
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
      result = Skill.transform_result(:click, error_result, context)

      assert {:error, enhanced} = result
      assert enhanced.diagnostics.url == "https://example.com"
      assert enhanced.diagnostics.title == "Test Page"
    end
  end
end
