defmodule Mix.Tasks.JidoBrowser.Install do
  @shortdoc "Install browser automation binaries (web, vibium)"
  @moduledoc """
  Install browser automation binaries for JidoBrowser.

  ## Usage

      # Install the default adapter's binary (based on config)
      mix jido_browser.install

      # Install specific binary
      mix jido_browser.install web
      mix jido_browser.install vibium

      # Install both
      mix jido_browser.install web vibium

  ## Options

      --path PATH      - Custom installation path (default: ~/.jido_browser/bin)
      --force          - Overwrite existing binaries
      --if-missing     - Only install if not already present (idempotent)

  ## Platform Support

  This installer automatically detects your platform:

  - **macOS** (Apple Silicon and Intel)
  - **Linux** (x86_64 and ARM64)
  - **Windows** (x86_64, vibium only)

  ## Recommended Setup

  Add to your `mix.exs` aliases for automatic installation:

      defp aliases do
        [
          setup: ["deps.get", "jido_browser.install --if-missing"],
          test: ["jido_browser.install --if-missing", "test"]
        ]
      end

  """
  use Mix.Task

  alias JidoBrowser.Installer

  @impl Mix.Task
  def run(args) do
    {opts, binaries, _} =
      OptionParser.parse(args,
        strict: [path: :string, force: :boolean, if_missing: :boolean]
      )

    if_missing = opts[:if_missing] || false
    force = opts[:force] || false
    install_path = opts[:path]

    binaries =
      case binaries do
        [] -> [default_binary()]
        list -> Enum.map(list, &String.to_atom/1)
      end

    Mix.shell().info("JidoBrowser Installer")
    Mix.shell().info("Platform: #{Installer.target()}")
    Mix.shell().info("")

    Enum.each(binaries, fn binary ->
      install_binary(binary, install_path, force, if_missing)
    end)
  end

  defp default_binary do
    adapter = Application.get_env(:jido_browser, :adapter, JidoBrowser.Adapters.Vibium)

    case adapter do
      JidoBrowser.Adapters.Vibium -> :vibium
      JidoBrowser.Adapters.Web -> :web
      _ -> :vibium
    end
  end

  defp install_binary(binary, install_path, force, if_missing) when binary in [:vibium, :web] do
    already_installed = Installer.installed?(binary)

    cond do
      if_missing and already_installed ->
        path = Installer.bin_path(binary)
        Mix.shell().info("✓ #{binary} already installed at #{path}")

      already_installed and not force ->
        path = Installer.bin_path(binary)
        Mix.shell().info("#{binary} already installed at #{path}. Use --force to reinstall.")

      true ->
        Mix.shell().info("Installing #{binary}...")

        opts = [force: force]
        opts = if install_path, do: Keyword.put(opts, :path, install_path), else: opts

        case Installer.install(binary, opts) do
          :ok ->
            Mix.shell().info("✓ #{binary} installed successfully")

          {:error, reason} ->
            Mix.shell().error("✗ Failed to install #{binary}: #{reason}")
        end
    end

    Mix.shell().info("")
  end

  defp install_binary(other, _install_path, _force, _if_missing) do
    Mix.shell().error("Unknown binary: #{other}. Use 'web' or 'vibium'.")
  end
end
