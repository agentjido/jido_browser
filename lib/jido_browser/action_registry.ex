defmodule Jido.Browser.ActionRegistry.Entry do
  @moduledoc "Metadata for one browser action."

  @enforce_keys [
    :action,
    :signal_name,
    :category,
    :tags,
    :support_level,
    :tool_contract_version
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          action: module(),
          signal_name: String.t(),
          category: atom(),
          tags: [String.t()],
          support_level: atom(),
          tool_contract_version: pos_integer()
        }
end

defmodule Jido.Browser.ActionRegistry do
  @moduledoc """
  Browser-owned metadata and stable ordering for the Jido Browser tool set.

  Action modules own execution and schemas. This registry owns discovery
  metadata that is specific to the browser tool catalog.
  """

  alias Jido.Browser.ActionRegistry.Entry

  @tool_contract_version 3
  @support_level :supported

  @entry_specs [
    # Session lifecycle
    {Jido.Browser.Actions.StartSession, "browser.start_session", :session, ["browser", "session", "lifecycle"]},
    {Jido.Browser.Actions.EndSession, "browser.end_session", :session, ["browser", "session", "lifecycle"]},
    {Jido.Browser.Actions.GetStatus, "browser.get_status", :session, ["browser", "session", "status"]},
    {Jido.Browser.Actions.PoolStatus, "browser.pool_status", :session, ["browser", "pool", "status", "diagnostics"]},
    {Jido.Browser.Actions.SaveState, "browser.save_state", :session, ["browser", "state", "session"]},
    {Jido.Browser.Actions.LoadState, "browser.load_state", :session, ["browser", "state", "session"]},
    # Navigation
    {Jido.Browser.Actions.Navigate, "browser.navigate", :navigation, ["browser", "navigation", "web"]},
    {Jido.Browser.Actions.Back, "browser.back", :navigation, ["browser", "navigation", "history", "web"]},
    {Jido.Browser.Actions.Forward, "browser.forward", :navigation, ["browser", "navigation", "history", "web"]},
    {Jido.Browser.Actions.Reload, "browser.reload", :navigation, ["browser", "navigation", "web"]},
    {Jido.Browser.Actions.GetUrl, "browser.get_url", :navigation, ["browser", "navigation", "web"]},
    {Jido.Browser.Actions.GetTitle, "browser.get_title", :navigation, ["browser", "navigation", "web"]},
    # Interaction
    {Jido.Browser.Actions.Click, "browser.click", :interaction, ["browser", "interaction", "web"]},
    {Jido.Browser.Actions.Type, "browser.type", :interaction, ["browser", "interaction", "input", "web"]},
    {Jido.Browser.Actions.Hover, "browser.hover", :interaction, ["browser", "interaction", "hover", "web"]},
    {Jido.Browser.Actions.Focus, "browser.focus", :interaction, ["browser", "interaction", "focus", "web"]},
    {Jido.Browser.Actions.Scroll, "browser.scroll", :interaction, ["browser", "interaction", "scroll", "web"]},
    {Jido.Browser.Actions.SelectOption, "browser.select_option", :interaction,
     ["browser", "interaction", "select", "form", "web"]},
    # Waiting and synchronization
    {Jido.Browser.Actions.Wait, "browser.wait", :synchronization, ["browser", "wait", "sync", "web"]},
    {Jido.Browser.Actions.WaitForSelector, "browser.wait_for_selector", :synchronization,
     ["browser", "wait", "sync", "web"]},
    {Jido.Browser.Actions.WaitForNavigation, "browser.wait_for_navigation", :synchronization,
     ["browser", "wait", "navigation", "web"]},
    # Element queries
    {Jido.Browser.Actions.Query, "browser.query", :query, ["browser", "query", "web"]},
    {Jido.Browser.Actions.GetText, "browser.get_text", :query, ["browser", "query", "web"]},
    {Jido.Browser.Actions.GetAttribute, "browser.get_attribute", :query, ["browser", "query", "web"]},
    {Jido.Browser.Actions.IsVisible, "browser.is_visible", :query, ["browser", "query", "web"]},
    # Tabs
    {Jido.Browser.Actions.ListTabs, "browser.tab_list", :tabs, ["browser", "tabs", "session"]},
    {Jido.Browser.Actions.NewTab, "browser.tab_new", :tabs, ["browser", "tabs", "navigation"]},
    {Jido.Browser.Actions.SwitchTab, "browser.tab_switch", :tabs, ["browser", "tabs", "navigation"]},
    {Jido.Browser.Actions.CloseTab, "browser.tab_close", :tabs, ["browser", "tabs", "session"]},
    # Content extraction
    {Jido.Browser.Actions.Snapshot, "browser.snapshot", :content,
     ["browser", "snapshot", "observe", "page", "web", "ai"]},
    {Jido.Browser.Actions.Screenshot, "browser.screenshot", :content, ["browser", "screenshot", "capture", "web"]},
    {Jido.Browser.Actions.ExtractContent, "browser.extract", :content,
     ["browser", "content", "extract", "markdown", "web"]},
    # Diagnostics
    {Jido.Browser.Actions.Console, "browser.console", :diagnostics, ["browser", "diagnostics", "console"]},
    {Jido.Browser.Actions.Errors, "browser.errors", :diagnostics, ["browser", "diagnostics", "errors"]},
    # Advanced
    {Jido.Browser.Actions.Evaluate, "browser.evaluate", :advanced, ["browser", "javascript", "evaluate", "web"]},
    # Self-contained composite actions
    {Jido.Browser.Actions.ReadPage, "browser.read_page", :composite, ["browser", "web", "read", "content", "markdown"]},
    {Jido.Browser.Actions.SnapshotUrl, "browser.snapshot_url", :composite,
     ["browser", "web", "snapshot", "observe", "ai"]},
    {Jido.Browser.Actions.SearchWeb, "browser.search_web", :composite, ["browser", "web", "search", "brave"]},
    {Jido.Browser.Actions.WebFetch, "browser.web_fetch", :composite, ["browser", "web", "fetch", "http", "retrieval"]},
    {Jido.Browser.Actions.FetchRich, "browser.fetch_rich", :composite,
     ["browser", "web", "fetch", "retrieval", "agent"]}
  ]

  @entries Enum.map(@entry_specs, fn {action, signal_name, category, tags} ->
             %Entry{
               action: action,
               signal_name: signal_name,
               category: category,
               tags: tags,
               support_level: @support_level,
               tool_contract_version: @tool_contract_version
             }
           end)

  for %Entry{action: action} <- @entries do
    Code.ensure_compiled!(action)
  end

  @doc "Returns all registry entries in stable tool order."
  @spec entries() :: [Entry.t()]
  def entries, do: @entries

  @doc "Returns all action modules in stable tool order."
  @spec actions() :: [module()]
  def actions, do: Enum.map(@entries, & &1.action)

  @doc "Returns all signal routes in stable tool order."
  @spec signal_routes() :: [{String.t(), module()}]
  def signal_routes, do: Enum.map(@entries, &{&1.signal_name, &1.action})

  @doc "Returns all signal names in stable tool order."
  @spec signal_patterns() :: [String.t()]
  def signal_patterns, do: Enum.map(@entries, & &1.signal_name)

  @doc "Returns the browser tool contract major version."
  @spec tool_contract_version() :: pos_integer()
  def tool_contract_version, do: @tool_contract_version

  @doc "Finds metadata by action module or signal name."
  @spec fetch(module() | String.t()) :: {:ok, Entry.t()} | :error
  def fetch(action_or_signal) do
    case Enum.find(@entries, &entry_matches?(&1, action_or_signal)) do
      nil -> :error
      entry -> {:ok, entry}
    end
  end

  @doc "Returns entries in one functional category."
  @spec by_category(atom()) :: [Entry.t()]
  def by_category(category), do: Enum.filter(@entries, &(&1.category == category))

  @doc "Returns entries that contain the specified tag."
  @spec with_tag(String.t()) :: [Entry.t()]
  def with_tag(tag), do: Enum.filter(@entries, &(tag in &1.tags))

  @doc "Returns entries at the specified support level."
  @spec by_support_level(atom()) :: [Entry.t()]
  def by_support_level(level), do: Enum.filter(@entries, &(&1.support_level == level))

  defp entry_matches?(%Entry{action: action}, action), do: true
  defp entry_matches?(%Entry{signal_name: signal_name}, signal_name), do: true
  defp entry_matches?(_entry, _key), do: false
end
