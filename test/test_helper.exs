ExUnit.start(exclude: [:integration])

# Enable Mimic for mocking
Mimic.copy(JidoBrowser)
Mimic.copy(JidoBrowser.Adapters.Vibium)
Mimic.copy(JidoBrowser.Adapters.Web)
