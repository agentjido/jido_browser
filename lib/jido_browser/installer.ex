defmodule JidoBrowser.Installer do
  @moduledoc """
  Binary installer for JidoBrowser adapters.

  This module handles downloading and installing the browser automation binaries
  (vibium, web) for all supported platforms. It follows the same patterns as
  Phoenix's Tailwind installer for a familiar experience.

  ## Supported Platforms

  - macOS (Apple Silicon and Intel)
  - Linux (x86_64 and ARM64)
  - Windows (x86_64)

  ## Usage

  Typically you won't call this module directly. Instead use:

      mix jido_browser.install

  Or configure automatic installation in your `mix.exs`:

      defp aliases do
        [
          setup: ["deps.get", "jido_browser.install --if-missing", ...]
        ]
      end

  """

  require Logger

  @vibium_version "1.0.0"
  @web_version "main"

  @type platform :: :darwin_arm64 | :darwin_amd64 | :linux_amd64 | :linux_arm64 | :windows_amd64

  @doc """
  Returns the detected platform for the current system.
  """
  @spec target() :: platform()
  def target do
    os = detect_os()
    arch = detect_arch()
    :"#{os}_#{arch}"
  end

  @doc """
  Returns whether a given binary is installed and available.
  """
  @spec installed?(atom()) :: boolean()
  def installed?(binary) when binary in [:vibium, :web] do
    case binary do
      :vibium -> vibium_installed?()
      :web -> web_installed?()
    end
  end

  @doc """
  Returns the path to the binary if installed, or nil.
  """
  @spec bin_path(atom()) :: String.t() | nil
  def bin_path(binary) when binary in [:vibium, :web] do
    case binary do
      :vibium -> find_vibium_path()
      :web -> find_web_path()
    end
  end

  @doc """
  Ensures the binary is installed. Returns :ok if already installed,
  or attempts to install if missing.

  ## Options

    * `:adapter` - The adapter to check/install (:vibium or :web)
    * `:force` - Force reinstallation even if already installed

  """
  @spec ensure_installed(keyword()) :: :ok | {:error, term()}
  def ensure_installed(opts \\ []) do
    adapter = opts[:adapter] || configured_adapter_binary()
    force = opts[:force] || false

    if force || not installed?(adapter) do
      install(adapter, opts)
    else
      :ok
    end
  end

  @doc """
  Installs the specified binary.
  """
  @spec install(atom(), keyword()) :: :ok | {:error, term()}
  def install(binary, opts \\ [])

  def install(:vibium, opts) do
    install_vibium(opts)
  end

  def install(:web, opts) do
    install_path = opts[:path] || default_install_path()
    force = opts[:force] || false
    install_web(install_path, force)
  end

  @doc """
  Returns the default installation path for binaries.

  Binaries are installed into `_build/jido_browser-TARGET` where TARGET
  is the platform identifier (e.g., `darwin_arm64`). This follows the
  same pattern as Phoenix's Tailwind installer.
  """
  @spec default_install_path() :: String.t()
  def default_install_path do
    if path = Application.get_env(:jido_browser, :path) do
      Path.expand(path)
    else
      Path.join(Path.dirname(Mix.Project.build_path()), "jido_browser-#{target()}")
    end
  end

  @doc """
  Returns the configured version for a binary.
  """
  @spec configured_version(atom()) :: String.t()
  def configured_version(:vibium), do: Application.get_env(:jido_browser, :vibium_version, @vibium_version)
  def configured_version(:web), do: Application.get_env(:jido_browser, :web_version, @web_version)

  # Private implementation

  defp configured_adapter_binary do
    adapter = Application.get_env(:jido_browser, :adapter, JidoBrowser.Adapters.Vibium)

    case adapter do
      JidoBrowser.Adapters.Vibium -> :vibium
      JidoBrowser.Adapters.Web -> :web
      _ -> :vibium
    end
  end

  defp vibium_installed? do
    case find_vibium_path() do
      nil -> false
      path -> File.exists?(path)
    end
  end

  defp web_installed? do
    case find_web_path() do
      nil -> false
      path -> File.exists?(path)
    end
  end

  defp find_vibium_path do
    case configured_path(:vibium) do
      path when is_binary(path) and path != "" ->
        if File.exists?(path), do: path, else: nil

      _ ->
        find_vibium_from_npm() || find_in_path("clicker") || find_in_jido_browser_bin("clicker")
    end
  end

  defp find_web_path do
    case configured_path(:web) do
      path when is_binary(path) and path != "" ->
        if File.exists?(path), do: path, else: nil

      _ ->
        find_in_path("web") || find_in_jido_browser_bin("web")
    end
  end

  defp configured_path(:vibium) do
    :jido_browser
    |> Application.get_env(:vibium, [])
    |> Keyword.get(:binary_path)
  end

  defp configured_path(:web) do
    :jido_browser
    |> Application.get_env(:web, [])
    |> Keyword.get(:binary_path)
  end

  defp find_in_path(binary_name) do
    System.find_executable(binary_name)
  end

  defp find_in_jido_browser_bin(binary_name) do
    path = Path.join(default_install_path(), binary_name)
    if File.exists?(path), do: path, else: nil
  end

  defp find_vibium_from_npm do
    case System.cmd("npm", ["root", "-g"], stderr_to_stdout: true) do
      {npm_root, 0} ->
        npm_root = String.trim(npm_root)
        platform_pkg = vibium_npm_package()
        clicker_path = Path.join([npm_root, platform_pkg, "bin", "clicker"])

        if File.exists?(clicker_path), do: clicker_path, else: nil

      _ ->
        nil
    end
  rescue
    _ -> nil
  end

  # Installation functions

  defp install_vibium(_opts) do
    case System.find_executable("npm") do
      nil ->
        {:error,
         "npm not found. Install Node.js first or install vibium manually from https://github.com/nicholasgriffintn/vibium"}

      npm ->
        platform_pkg = vibium_npm_package()
        Logger.info("Installing vibium via npm...")

        case System.cmd(npm, ["install", "-g", "vibium", platform_pkg], stderr_to_stdout: true) do
          {_output, 0} ->
            run_vibium_chrome_install()
            :ok

          {output, code} ->
            {:error, "npm install failed (exit #{code}): #{output}"}
        end
    end
  end

  defp run_vibium_chrome_install do
    case find_vibium_path() do
      nil ->
        Logger.warning("Could not find clicker binary to run Chrome install")

      clicker ->
        Logger.info("Installing Chrome for Testing...")

        case System.cmd(clicker, ["install"], stderr_to_stdout: true) do
          {_output, 0} -> :ok
          {output, code} -> Logger.warning("Chrome install returned #{code}: #{output}")
        end
    end
  end

  defp install_web(install_path, force) do
    target = Path.join(install_path, web_binary_name())

    if File.exists?(target) and not force do
      Logger.info("web already installed at #{target}. Use --force to overwrite.")
      :ok
    else
      File.mkdir_p!(install_path)
      url = web_download_url()
      Logger.info("Downloading web from #{url}...")
      download_binary(url, target)
    end
  end

  defp web_binary_name do
    case target() do
      :windows_amd64 -> "web.exe"
      _ -> "web"
    end
  end

  defp web_download_url do
    platform = target()

    base_url = "https://raw.githubusercontent.com/chrismccord/web/#{configured_version(:web)}"

    case platform do
      :darwin_arm64 -> "#{base_url}/web-darwin-arm64"
      :darwin_amd64 -> "#{base_url}/web-darwin-amd64"
      :linux_amd64 -> "#{base_url}/web-linux-amd64"
      :linux_arm64 -> "#{base_url}/web-linux-arm64"
      :windows_amd64 -> raise "Windows is not currently supported for the web adapter"
    end
  end

  defp vibium_npm_package do
    case target() do
      :darwin_arm64 -> "@vibium/darwin-arm64"
      :darwin_amd64 -> "@vibium/darwin-x64"
      :linux_amd64 -> "@vibium/linux-x64"
      :linux_arm64 -> "@vibium/linux-arm64"
      :windows_amd64 -> "@vibium/win32-x64"
    end
  end

  defp download_binary(url, target) do
    case http_download(url) do
      {:ok, body} ->
        File.write!(target, body)
        File.chmod!(target, 0o755)
        Logger.info("✓ Installed to #{target}")
        :ok

      {:error, reason} ->
        {:error, "Download failed: #{reason}"}
    end
  end

  defp http_download(url) do
    Application.ensure_all_started(:inets)
    Application.ensure_all_started(:ssl)

    url_charlist = String.to_charlist(url)

    http_options = [
      ssl: [
        verify: :verify_peer,
        cacerts: :public_key.cacerts_get(),
        customize_hostname_check: [
          match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
        ]
      ],
      timeout: 60_000,
      autoredirect: true
    ]

    case :httpc.request(:get, {url_charlist, []}, http_options, body_format: :binary) do
      {:ok, {{_, 200, _}, _headers, body}} ->
        {:ok, body}

      {:ok, {{_, status, _}, _headers, body}} ->
        {:error, "HTTP #{status}: #{body}"}

      {:error, reason} ->
        {:error, inspect(reason)}
    end
  end

  # Platform detection

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
  defp parse_arch("win32" <> _), do: :amd64
  defp parse_arch(_other), do: :amd64
end
