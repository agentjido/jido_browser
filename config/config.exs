import Config

config :jido_browser,
  adapter: JidoBrowser.Adapters.Vibium,
  timeout: 30_000

import_config "#{config_env()}.exs"
