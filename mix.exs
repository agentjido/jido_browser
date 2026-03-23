defmodule Jido.Browser.MixProject do
  use Mix.Project

  @version "2.0.0"
  @source_url "https://github.com/agentjido/jido_browser"
  @description "Browser automation actions for Jido AI agents"
  @otp_release List.to_string(:erlang.system_info(:otp_release))
  @dialyzer_plt "priv/plts/dialyzer-otp#{@otp_release}.plt"

  def project do
    [
      app: :jido_browser,
      version: @version,
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),

      # Documentation
      name: "Jido Browser",
      description: @description,
      source_url: @source_url,
      homepage_url: @source_url,
      docs: docs(),

      # Hex
      package: package(),

      # Dialyzer
      dialyzer: dialyzer(),

      # Test coverage
      test_coverage: [tool: ExCoveralls]
    ]
  end

  def cli do
    [
      preferred_envs: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.html": :test,
        "coveralls.json": :test,
        quality: :test
      ]
    ]
  end

  def application do
    [
      mod: {Jido.Browser.Application, []},
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # Jido ecosystem
      {:jido, "~> 2.1"},
      {:jido_action, "~> 2.1"},

      # Runtime
      {:zoi, "~> 0.16"},
      {:splode, "~> 0.3.0"},
      {:req, "~> 0.5"},
      {:jason, "~> 1.4"},
      {:uniq, "~> 0.6"},
      {:floki, "~> 0.38"},
      {:html2markdown, "~> 0.3"},
      {:extractous_ex, "~> 0.2"},
      {:nimble_pool, "~> 1.1"},

      # Dev/Test
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:doctor, "~> 0.21", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18", only: [:dev, :test]},
      {:git_ops, "~> 2.9", only: :dev, runtime: false},
      {:git_hooks, "~> 0.8", only: [:dev, :test], runtime: false},
      {:mimic, "~> 2.3", only: :test}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "deps.compile"],
      quality: [
        "compile --warnings-as-errors",
        "format --check-formatted",
        "credo --strict",
        "dialyzer",
        "doctor --raise"
      ],
      q: ["quality"]
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url: @source_url,
      extras: [
        "README.md": [title: "Overview"],
        "CHANGELOG.md": [title: "Changelog"],
        LICENSE: [title: "License"]
      ],
      groups_for_modules: [
        Core: [
          Jido.Browser,
          Jido.Browser.Pool,
          Jido.Browser.Session,
          Jido.Browser.Plugin,
          Jido.Browser.WebFetch
        ],
        Adapters: [
          Jido.Browser.Adapter,
          Jido.Browser.Adapters.AgentBrowser,
          Jido.Browser.Adapters.Vibium,
          Jido.Browser.Adapters.Web
        ],
        "Session Lifecycle": [
          Jido.Browser.Actions.StartSession,
          Jido.Browser.Actions.EndSession,
          Jido.Browser.Actions.GetStatus
        ],
        Navigation: [
          Jido.Browser.Actions.Navigate,
          Jido.Browser.Actions.Back,
          Jido.Browser.Actions.Forward,
          Jido.Browser.Actions.Reload,
          Jido.Browser.Actions.GetUrl,
          Jido.Browser.Actions.GetTitle
        ],
        Interaction: [
          Jido.Browser.Actions.Click,
          Jido.Browser.Actions.Type,
          Jido.Browser.Actions.Hover,
          Jido.Browser.Actions.Focus,
          Jido.Browser.Actions.Scroll,
          Jido.Browser.Actions.SelectOption
        ],
        Waiting: [
          Jido.Browser.Actions.Wait,
          Jido.Browser.Actions.WaitForSelector,
          Jido.Browser.Actions.WaitForNavigation
        ],
        "Element Queries": [
          Jido.Browser.Actions.Query,
          Jido.Browser.Actions.GetText,
          Jido.Browser.Actions.GetAttribute,
          Jido.Browser.Actions.IsVisible
        ],
        "Content Extraction": [
          Jido.Browser.Actions.Snapshot,
          Jido.Browser.Actions.Screenshot,
          Jido.Browser.Actions.ExtractContent,
          Jido.Browser.Actions.WebFetch
        ],
        Advanced: [
          Jido.Browser.Actions.Evaluate
        ],
        Errors: [
          Jido.Browser.Error
        ]
      ]
    ]
  end

  defp package do
    [
      name: "jido_browser",
      files: ~w(lib .formatter.exs mix.exs README.md LICENSE CHANGELOG.md),
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md"
      }
    ]
  end

  defp dialyzer do
    [
      plt_file: {:no_warn, @dialyzer_plt},
      plt_add_apps: [:mix, :ex_unit],
      flags: [
        :error_handling,
        :unknown
      ],
      ignore_warnings: ".dialyzer_ignore.exs"
    ]
  end
end
