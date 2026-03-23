ExUnit.start(exclude: [:integration])

# Enable Mimic for mocking
Mimic.copy(Jido.Browser)
Mimic.copy(Jido.Browser.Adapters.AgentBrowser)
Mimic.copy(Jido.Browser.Adapters.Vibium)
Mimic.copy(Jido.Browser.Adapters.Web)
Mimic.copy(Jido.Browser.AgentBrowser.Runtime)
