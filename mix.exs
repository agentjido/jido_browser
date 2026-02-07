defmodule JidoBrowser.MixProject do
  use Mix.Project

  @version "0.8.1"
  @source_url "https://github.com/agentjido/jido_browser"
  @description "Browser automation actions for Jido AI agents"

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
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # Jido ecosystem
      {:jido, "~> 2.0.0-rc.4"},
      {:jido_action, "~> 2.0.0-rc.4"},

      # Runtime
      {:zoi, "~> 0.16"},
      {:splode, "~> 0.3.0"},
      {:req, "~> 0.5"},
      {:jason, "~> 1.4"},
      {:uniq, "~> 0.6"},

      # Dev/Test
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:doctor, "~> 0.21", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18", only: [:dev, :test]},
      {:git_hooks, "~> 0.8", only: [:dev, :test], runtime: false},
      {:mimic, "~> 1.11", only: :test}
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
          JidoBrowser,
          JidoBrowser.Session,
          JidoBrowser.Plugin
        ],
        Adapters: [
          JidoBrowser.Adapter,
          JidoBrowser.Adapters.Vibium,
          JidoBrowser.Adapters.Web
        ],
        "Session Lifecycle": [
          JidoBrowser.Actions.StartSession,
          JidoBrowser.Actions.EndSession,
          JidoBrowser.Actions.GetStatus
        ],
        Navigation: [
          JidoBrowser.Actions.Navigate,
          JidoBrowser.Actions.Back,
          JidoBrowser.Actions.Forward,
          JidoBrowser.Actions.Reload,
          JidoBrowser.Actions.GetUrl,
          JidoBrowser.Actions.GetTitle
        ],
        Interaction: [
          JidoBrowser.Actions.Click,
          JidoBrowser.Actions.Type,
          JidoBrowser.Actions.Hover,
          JidoBrowser.Actions.Focus,
          JidoBrowser.Actions.Scroll,
          JidoBrowser.Actions.SelectOption
        ],
        Waiting: [
          JidoBrowser.Actions.Wait,
          JidoBrowser.Actions.WaitForSelector,
          JidoBrowser.Actions.WaitForNavigation
        ],
        "Element Queries": [
          JidoBrowser.Actions.Query,
          JidoBrowser.Actions.GetText,
          JidoBrowser.Actions.GetAttribute,
          JidoBrowser.Actions.IsVisible
        ],
        "Content Extraction": [
          JidoBrowser.Actions.Snapshot,
          JidoBrowser.Actions.Screenshot,
          JidoBrowser.Actions.ExtractContent
        ],
        Advanced: [
          JidoBrowser.Actions.Evaluate
        ],
        Errors: [
          JidoBrowser.Error
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
      plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
      plt_add_apps: [:mix, :ex_unit],
      flags: [
        :error_handling,
        :unknown
      ],
      ignore_warnings: ".dialyzer_ignore.exs"
    ]
  end
end
