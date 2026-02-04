defmodule Mix.Tasks.Compile.JidoBrowser do
  @shortdoc "Checks for JidoBrowser binary dependencies"
  @moduledoc """
  A Mix compiler that checks if the browser automation binary is installed.

  This compiler runs during `mix compile` and emits a helpful warning if the
  required binary for the configured adapter is not found.

  ## Configuration

  Add this compiler to your project's `mix.exs`:

      def project do
        [
          compilers: [:jido_browser] ++ Mix.compilers(),
          ...
        ]
      end

  Or add it via aliases for a gentler approach:

      defp aliases do
        [
          compile: ["compile.jido_browser", "compile"]
        ]
      end

  """
  use Mix.Task.Compiler

  alias JidoBrowser.Installer

  @impl Mix.Task.Compiler
  def run(_args) do
    adapter = Application.get_env(:jido_browser, :adapter, JidoBrowser.Adapters.Vibium)

    binary =
      case adapter do
        JidoBrowser.Adapters.Vibium -> :vibium
        JidoBrowser.Adapters.Web -> :web
        _ -> :vibium
      end

    if Installer.installed?(binary) do
      {:ok, []}
    else
      platform = Installer.target()

      warning = """

      ════════════════════════════════════════════════════════════════════════════════
      JidoBrowser: Browser binary not found!

      The #{binary} binary is required but not installed.
      Detected platform: #{platform}

      To install, run:

          mix jido_browser.install

      Or add to your mix.exs aliases for automatic installation:

          defp aliases do
            [
              setup: ["deps.get", "jido_browser.install --if-missing"]
            ]
          end

      ════════════════════════════════════════════════════════════════════════════════
      """

      Mix.shell().info(warning)
      {:ok, []}
    end
  end
end
