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
        vsn: 3,
        option_keys: [agent: [:headless, :timeout, :adapter, :pool, :checkout_timeout, :viewport, :base_url]]

      @doc false
      @impl Jido.Plugin
      def state_spec(opts) do
        :ok = ProfileContract.reject_profile_option!(Map.new(opts))
        {:browser, ProfileContract.state_schema()}
      end

      @doc false
      @impl Jido.Plugin
      def prepare(%Jido.Agent.Plugin.Preparation{plugin_state: state}, _opts), do: {:ok, state}

      @doc false
      @impl Jido.Plugin
      def reduce(%Jido.Agent.Plugin.Reduction{plugin_state: state}, _opts), do: {:ok, state}

      @doc false
      def name, do: "browser"
      @doc false
      def state_key, do: :browser

      @doc "Returns the Actions in this static browser tool profile."
      @spec actions() :: [module()]
      def actions, do: unquote(actions)

      @doc false
      def schema, do: ProfileContract.state_schema()
      @doc false
      def config_schema, do: ProfileContract.config_schema()

      @doc "Returns the Signal patterns in this static browser tool profile."
      @spec signal_patterns() :: [String.t()]
      def signal_patterns, do: unquote(signal_patterns)

      @doc "Returns the Signal routes in this static browser tool profile."
      @spec signal_routes() :: [{String.t(), module()}]
      def signal_routes, do: unquote(Macro.escape(signal_routes))

      @doc false
      def signal_routes(config) do
        :ok = ProfileContract.reject_profile_option!(config)
        signal_routes()
      end

      @doc false
      def description, do: "Browser automation for web navigation, interaction, and content extraction"
      @doc false
      def category, do: "browser"
      @doc false
      def tags, do: ["browser", "web", "automation", "scraping"]
      @doc false
      def vsn, do: "3.0.0"

      @doc false
      def manifest do
        %{
          name: name(),
          state_key: state_key(),
          actions: actions(),
          schema: schema(),
          config_schema: config_schema(),
          signal_patterns: signal_patterns(),
          signal_routes: signal_routes(),
          description: description(),
          category: category(),
          tags: tags(),
          vsn: vsn()
        }
      end

      @doc false
      def plugin_spec(config) do
        :ok = ProfileContract.reject_profile_option!(config)
        manifest()
      end
    end
  end
end
