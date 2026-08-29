defmodule Jido.Browser.Plugin.Profile do
  @moduledoc false

  alias Jido.Browser.ActionRegistry

  @state_schema Zoi.object(%{
                  session: Zoi.any(description: "Active browser session") |> Zoi.optional(),
                  headless: Zoi.boolean(description: "Run browser in headless mode") |> Zoi.default(true),
                  timeout: Zoi.integer(description: "Default timeout in milliseconds") |> Zoi.default(30_000),
                  adapter: Zoi.atom(description: "Browser adapter module") |> Zoi.optional(),
                  pool: Zoi.any(description: "Named warm session pool") |> Zoi.optional(),
                  checkout_timeout:
                    Zoi.integer(description: "Warm pool checkout timeout in milliseconds") |> Zoi.default(5_000),
                  viewport: Zoi.any(description: "Browser viewport dimensions") |> Zoi.optional(),
                  base_url: Zoi.string(description: "Base URL for relative navigation") |> Zoi.optional(),
                  last_url: Zoi.string(description: "Last navigated URL") |> Zoi.optional(),
                  last_title: Zoi.string(description: "Last page title") |> Zoi.optional(),
                  seen_urls:
                    Zoi.array(Zoi.string(description: "Known URLs discovered during tool use")) |> Zoi.default([]),
                  web_fetch_uses:
                    Zoi.integer(description: "Successful web fetch calls in current skill state") |> Zoi.default(0),
                  fetch_rich_uses:
                    Zoi.integer(description: "Successful rich fetch calls in current skill state") |> Zoi.default(0)
                })

  @config_schema Zoi.object(
                   %{
                     headless: Zoi.boolean(description: "Run browser in headless mode") |> Zoi.default(true),
                     timeout: Zoi.integer(description: "Default timeout in milliseconds") |> Zoi.default(30_000),
                     adapter: Zoi.atom(description: "Browser adapter module") |> Zoi.optional(),
                     pool: Zoi.any(description: "Named warm session pool") |> Zoi.optional(),
                     checkout_timeout:
                       Zoi.integer(description: "Warm pool checkout timeout in milliseconds") |> Zoi.default(5_000),
                     viewport: Zoi.any(description: "Browser viewport dimensions") |> Zoi.optional(),
                     base_url: Zoi.string(description: "Base URL for relative navigation") |> Zoi.optional()
                   },
                   unrecognized_keys: :error
                 )

  @doc "Returns the compiler-static browser plugin state schema."
  @spec state_schema() :: Zoi.schema()
  def state_schema, do: @state_schema

  @doc "Returns the compiler-static browser plugin configuration schema."
  @spec config_schema() :: Zoi.schema()
  def config_schema, do: @config_schema

  @doc "Rejects the removed configuration-dependent profile option."
  @spec reject_profile_option!(map()) :: :ok
  def reject_profile_option!(config) when is_map(config) do
    if Map.has_key?(config, :profile) or Map.has_key?(config, "profile") do
      raise ArgumentError,
            "the :profile option is not supported; use Jido.Browser.Plugin.Debug or Jido.Browser.Plugin.All"
    end

    :ok
  end

  @doc "Builds a browser plugin module for one static registry profile."
  defmacro __using__(opts) do
    profile = Keyword.fetch!(opts, :profile)
    actions = ActionRegistry.actions(profile)
    signal_patterns = ActionRegistry.signal_patterns(profile)
    signal_routes = ActionRegistry.signal_routes(profile)

    quote do
      alias Jido.Browser.Plugin.Profile, as: ProfileContract

      use Jido.Plugin,
        name: "browser",
        state_key: :browser,
        actions: unquote(actions),
        schema: unquote(Macro.escape(@state_schema)),
        config_schema: unquote(Macro.escape(@config_schema)),
        signal_patterns: unquote(signal_patterns),
        signal_routes: unquote(Macro.escape(signal_routes)),
        description: "Browser automation for web navigation, interaction, and content extraction",
        category: "browser",
        tags: ["browser", "web", "automation", "scraping"],
        vsn: "2.0.0"

      defoverridable plugin_spec: 1

      @impl Jido.Plugin
      def plugin_spec(config) do
        :ok = ProfileContract.reject_profile_option!(config)
        super(config)
      end

      @impl Jido.Plugin
      def signal_routes(_config), do: signal_routes()
    end
  end
end
