# Run with: mix run example_tabs.exs

alias Jido.Browser

{:ok, session} = Browser.start_session()

try do
  {:ok, session, _nav_result} = Browser.navigate(session, "https://example.com")
  {:ok, session, _new_tab_result} = Browser.new_tab(session, "https://example.org")

  {:ok, _session, tabs_result} = Browser.list_tabs(session)
  IO.inspect(tabs_result, label: "Open tabs")

  {:ok, session, _switch_result} = Browser.switch_tab(session, 0)
  {:ok, _session, first_tab_url} = Browser.get_url(session)
  IO.puts("Tab 0 URL: #{first_tab_url["url"] || first_tab_url[:url]}")

  {:ok, session, _switch_result} = Browser.switch_tab(session, 1)
  {:ok, _session, second_tab_url} = Browser.get_url(session)
  IO.puts("Tab 1 URL: #{second_tab_url["url"] || second_tab_url[:url]}")

  {:ok, _session, _close_result} = Browser.close_tab(session, 1)
after
  Browser.end_session(session)
end
