import Config

config :jido_browser,
  adapter: Jido.Browser.Adapters.AgentBrowser,
  timeout: 30_000

import_config "#{config_env()}.exs"
