defmodule Mix.Tasks.JidoBrowser.Install do
  @shortdoc "Install browser automation binaries (web, vibium)"
  @moduledoc """
  Install browser automation binaries for JidoBrowser.

  ## Usage

      # Install all binaries
      mix jido_browser.install

      # Install specific binary
      mix jido_browser.install web
      mix jido_browser.install vibium

  ## Options

      --path PATH  - Custom installation path (default: ~/bin)
      --force      - Overwrite existing binaries

  """
  use Mix.Task

  @default_install_path Path.expand("~/bin")

  @impl Mix.Task
  def run(args) do
    {opts, binaries, _} =
      OptionParser.parse(args, strict: [path: :string, force: :boolean])

    install_path = opts[:path] || @default_install_path
    force? = opts[:force] || false

    File.mkdir_p!(install_path)

    binaries = if binaries == [], do: ["web", "vibium"], else: binaries

    Enum.each(binaries, fn binary ->
      case binary do
        "web" -> install_web(install_path, force?)
        "vibium" -> install_vibium(install_path, force?)
        other -> Mix.shell().error("Unknown binary: #{other}. Use 'web' or 'vibium'.")
      end
    end)
  end

  defp install_web(install_path, force?) do
    target = Path.join(install_path, "web")

    if File.exists?(target) and not force? do
      Mix.shell().info("web already installed at #{target}. Use --force to overwrite.")
      :ok
    else
      Mix.shell().info("Installing web CLI...")

      platform = detect_platform()

      url =
        case platform do
          :darwin_arm64 ->
            "https://raw.githubusercontent.com/chrismccord/web/main/web-darwin-arm64"

          :darwin_amd64 ->
            "https://raw.githubusercontent.com/chrismccord/web/main/web-darwin-amd64"

          :linux_amd64 ->
            "https://raw.githubusercontent.com/chrismccord/web/main/web-linux-amd64"

          _ ->
            Mix.raise("Unsupported platform: #{platform}")
        end

      download_binary(url, target)
      Mix.shell().info("✓ web installed to #{target}")
    end
  end

  defp install_vibium(_install_path, _force?) do
    Mix.shell().info("Installing vibium via npm...")

    case System.find_executable("npm") do
      nil ->
        Mix.raise("npm not found. Install Node.js first or install vibium manually.")

      npm ->
        platform_pkg = vibium_platform_package()

        case System.cmd(npm, ["install", "-g", "vibium", platform_pkg], stderr_to_stdout: true) do
          {output, 0} ->
            Mix.shell().info(output)
            run_vibium_install()
            Mix.shell().info("✓ vibium installed globally via npm")

          {output, code} ->
            Mix.shell().error("npm install failed (exit #{code}): #{output}")
        end
    end
  end

  defp run_vibium_install do
    case find_clicker_binary() do
      nil ->
        Mix.shell().warn("Could not find clicker binary to run install")

      clicker ->
        Mix.shell().info("Installing Chrome for Testing...")

        case System.cmd(clicker, ["install"], stderr_to_stdout: true) do
          {output, 0} ->
            Mix.shell().info(output)

          {output, code} ->
            Mix.shell().warn("Chrome install returned #{code}: #{output}")
        end
    end
  end

  defp find_clicker_binary do
    case System.cmd("npm", ["root", "-g"], stderr_to_stdout: true) do
      {npm_root, 0} ->
        npm_root = String.trim(npm_root)
        platform_pkg = vibium_platform_package()
        clicker_path = Path.join([npm_root, platform_pkg, "bin", "clicker"])

        if File.exists?(clicker_path), do: clicker_path, else: nil

      _ ->
        nil
    end
  rescue
    _ -> nil
  end

  defp vibium_platform_package do
    platform = detect_platform()

    case platform do
      :darwin_arm64 -> "@vibium/darwin-arm64"
      :darwin_amd64 -> "@vibium/darwin-x64"
      :linux_amd64 -> "@vibium/linux-x64"
      :linux_arm64 -> "@vibium/linux-arm64"
      _ -> Mix.raise("Unsupported platform for vibium: #{platform}")
    end
  end

  defp download_binary(url, target) do
    Mix.shell().info("Downloading from #{url}...")

    case System.cmd("curl", ["-L", "-o", target, url], stderr_to_stdout: true) do
      {_, 0} ->
        File.chmod!(target, 0o755)

      {output, code} ->
        Mix.raise("Download failed (exit #{code}): #{output}")
    end
  end

  defp detect_platform do
    os = detect_os()
    arch = detect_arch()
    :"#{os}_#{arch}"
  end

  defp detect_os do
    case :os.type() do
      {:unix, :darwin} -> :darwin
      {:unix, :linux} -> :linux
      {:win32, _} -> :windows
      other -> other
    end
  end

  defp detect_arch do
    :erlang.system_info(:system_architecture)
    |> to_string()
    |> parse_arch()
  end

  defp parse_arch("aarch64" <> _), do: :arm64
  defp parse_arch("arm64" <> _), do: :arm64
  defp parse_arch("x86_64" <> _), do: :amd64
  defp parse_arch("amd64" <> _), do: :amd64
  defp parse_arch(other), do: String.to_atom(other)
end
