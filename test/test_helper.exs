ExUnit.start(exclude: [:integration])

web_fetch_config = Application.get_env(:jido_browser, :web_fetch, [])

Application.put_env(
  :jido_browser,
  :web_fetch,
  Keyword.put(web_fetch_config, :resolver, Jido.Browser.TestSupport.WebFetchResolver)
)

# Enable Mimic for mocking
Mimic.copy(Jido.Browser)
Mimic.copy(Jido.Browser.Adapters.AgentBrowser)
Mimic.copy(Jido.Browser.Adapters.Test)
Mimic.copy(Jido.Browser.Adapters.Vibium)
Mimic.copy(Jido.Browser.AgentBrowser.Runtime)
