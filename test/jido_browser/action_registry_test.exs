defmodule Jido.Browser.ActionRegistryTest do
  use ExUnit.Case, async: true

  alias Jido.Browser.ActionRegistry
  alias Jido.Browser.ActionRegistry.Entry
  alias Jido.Browser.Actions

  @category_contract [
    session: [
      Actions.StartSession,
      Actions.EndSession,
      Actions.GetStatus,
      Actions.PoolStatus,
      Actions.SaveState,
      Actions.LoadState
    ],
    navigation: [
      Actions.Navigate,
      Actions.Back,
      Actions.Forward,
      Actions.Reload,
      Actions.GetUrl,
      Actions.GetTitle
    ],
    interaction: [
      Actions.Click,
      Actions.Type,
      Actions.Hover,
      Actions.Focus,
      Actions.Scroll,
      Actions.SelectOption
    ],
    synchronization: [Actions.Wait, Actions.WaitForSelector, Actions.WaitForNavigation],
    query: [Actions.Query, Actions.GetText, Actions.GetAttribute, Actions.IsVisible],
    tabs: [Actions.ListTabs, Actions.NewTab, Actions.SwitchTab, Actions.CloseTab],
    content: [Actions.Snapshot, Actions.Screenshot, Actions.ExtractContent],
    diagnostics: [Actions.Console, Actions.Errors],
    advanced: [Actions.Evaluate],
    composite: [Actions.ReadPage, Actions.SnapshotUrl, Actions.SearchWeb, Actions.WebFetch, Actions.FetchRich]
  ]

  test "owns complete metadata in stable tool order" do
    entries = ActionRegistry.entries()
    expected_actions = Enum.flat_map(@category_contract, &elem(&1, 1))

    assert length(entries) == 40
    assert Enum.map(entries, & &1.action) == expected_actions
    assert ActionRegistry.actions() == expected_actions
    assert ActionRegistry.tool_contract_version() == 3

    for entry <- entries do
      assert %Entry{} = entry
      assert entry.support_level == :supported
      assert entry.tool_contract_version == 3
      assert "browser" in entry.tags
      assert String.starts_with?(entry.signal_name, "browser.")
    end

    assert length(Enum.uniq_by(entries, & &1.action)) == 40
    assert length(Enum.uniq_by(entries, & &1.signal_name)) == 40
  end

  test "groups and filters registry entries" do
    for {category, expected_actions} <- @category_contract do
      assert ActionRegistry.by_category(category) |> Enum.map(& &1.action) == expected_actions
    end

    assert ActionRegistry.with_tag("diagnostics") |> Enum.map(& &1.action) == [
             Actions.PoolStatus,
             Actions.Console,
             Actions.Errors
           ]

    assert ActionRegistry.by_support_level(:supported) == ActionRegistry.entries()
    assert ActionRegistry.by_support_level(:unsupported) == []
  end

  test "looks up metadata by action or signal name" do
    assert {:ok, %Entry{} = by_action} = ActionRegistry.fetch(Actions.Navigate)
    assert {:ok, %Entry{} = by_signal} = ActionRegistry.fetch("browser.navigate")
    assert by_action == by_signal
    assert by_action.category == :navigation
    assert "navigation" in by_action.tags
    assert ActionRegistry.fetch("browser.unknown") == :error
  end

  test "keeps Action definitions free of browser catalog metadata" do
    for action <- ActionRegistry.actions() do
      assert action.category() == nil
      assert action.tags() == []
      assert action.vsn() == nil
    end
  end
end
