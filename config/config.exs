import Config

config :jido_browser,
  adapter: JidoBrowser.Adapters.Web,
  timeout: 30_000

import_config "#{config_env()}.exs"
