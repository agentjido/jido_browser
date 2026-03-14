# Run with: iex -S mix

defmodule ExampleBrowsingAgent do
  use Jido.Agent,
    name: "agent_browser_demo",
    description: "Example agent configured with the Jido.Browser plugin",
    plugins: [
      {Jido.Browser.Plugin,
       [
         adapter: Jido.Browser.Adapters.AgentBrowser,
         headless: true,
         timeout: 30_000
       ]}
    ]
end

IO.puts("""
Defined ExampleBrowsingAgent.

From iex you can now experiment with browser.* actions such as:
  - browser.start_session
  - browser.snapshot
  - browser.tab_new
  - browser.save_state
""")
