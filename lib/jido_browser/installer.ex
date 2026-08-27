defmodule Jido.Browser.Installer do
  @moduledoc """
  Binary installer for Jido.Browser adapters.

  This module handles downloading and installing the browser automation binaries
  (vibium, web, lightpanda) for all supported platforms. It follows the same patterns as
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

  @compile {:no_warn_undefined, LightpandaEx}
  require Logger

  alias Jido.Browser.AgentBrowser.Binary

  @vibium_version "26.3.11"
  @web_version "main"
  @lightpanda_version "0.3.0"
  @command_probes %{
    vibium: ["version"],
    web: ["--help"],
    lightpanda: ["version"]
  }

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
  def installed?(binary) when binary in [:agent_browser, :vibium, :web, :lightpanda] do
    case binary do
      :agent_browser -> agent_browser_installed?()
      :vibium -> vibium_installed?()
      :web -> web_installed?()
      :lightpanda -> lightpanda_installed?()
    end
  end

  @doc """
  Returns the path to the binary if installed, or nil.
  """
  @spec bin_path(atom()) :: String.t() | nil
  def bin_path(binary) when binary in [:agent_browser, :vibium, :web, :lightpanda] do
    case binary do
      :agent_browser -> find_agent_browser_path()
      :vibium -> find_vibium_path()
      :web -> find_web_path()
      :lightpanda -> find_lightpanda_path()
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

    cond do
      adapter == :agent_browser -> ensure_agent_browser_installed(opts, force)
      force || not installed?(adapter) -> install(adapter, opts)
      true -> :ok
    end
  end

  @doc """
  Installs the specified binary.
  """
  @spec install(atom(), keyword()) :: :ok | {:error, term()}
  def install(binary, opts \\ [])

  def install(:agent_browser, opts) do
    if configured_agent_browser_path?() do
      case resolve_agent_browser() do
        {:ok, _path} -> :ok
        {:error, reason} -> {:error, reason}
      end
    else
      install_path = opts[:path] || default_install_path()
      force = opts[:force] || false
      install_agent_browser(install_path, force)
    end
  end

  def install(:vibium, opts) do
    verify_effective_install(:vibium, install_vibium(opts), opts)
  end

  def install(:web, opts) do
    install_path = opts[:path] || default_install_path()
    force = opts[:force] || false

    verify_effective_install(:web, install_web(install_path, force), opts)
  end

  def install(:lightpanda, opts) do
    verify_effective_install(:lightpanda, install_lightpanda(opts), opts)
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

  @doc false
  @spec agent_browser_package_path() :: String.t()
  def agent_browser_package_path do
    Path.join(default_install_path(), agent_browser_binary_name())
  end

  @doc """
  Returns the configured version for a binary.
  """
  @spec configured_version(atom()) :: String.t()
  def configured_version(:agent_browser), do: Binary.supported_version()

  def configured_version(:vibium), do: Application.get_env(:jido_browser, :vibium_version, @vibium_version)
  def configured_version(:web), do: Application.get_env(:jido_browser, :web_version, @web_version)
  def configured_version(:lightpanda), do: Application.get_env(:jido_browser, :lightpanda_version, lightpanda_version())

  # Private implementation

  defp configured_adapter_binary do
    adapter = Application.get_env(:jido_browser, :adapter, Jido.Browser.Adapters.AgentBrowser)

    case adapter do
      Jido.Browser.Adapters.AgentBrowser -> :agent_browser
      Jido.Browser.Adapters.Vibium -> :vibium
      Jido.Browser.Adapters.Web -> :web
      Jido.Browser.Adapters.Lightpanda -> :lightpanda
      _ -> :agent_browser
    end
  end

  defp agent_browser_installed? do
    match?({:ok, _path}, resolve_agent_browser())
  end

  defp vibium_installed? do
    case find_vibium_path() do
      nil -> false
      path -> command_usable?(path, @command_probes.vibium)
    end
  end

  defp web_installed? do
    case find_web_path() do
      nil -> false
      path -> command_usable?(path, @command_probes.web)
    end
  end

  defp lightpanda_installed? do
    case find_lightpanda_path() do
      nil -> false
      path -> command_usable?(path, @command_probes.lightpanda)
    end
  end

  defp command_usable?(path, args) do
    match?({_output, 0}, System.cmd(path, args, stderr_to_stdout: true))
  rescue
    _error -> false
  end

  defp verify_effective_install(binary, :ok, opts) do
    if effective_install_usable?(binary, opts) do
      :ok
    else
      {:error, effective_install_error(binary, bin_path(binary))}
    end
  end

  defp verify_effective_install(_binary, result, _opts), do: result

  defp effective_install_usable?(binary, opts) do
    case configured_path(binary) do
      path when path not in [nil, ""] -> installed?(binary)
      _path -> is_binary(opts[:path]) || installed?(binary)
    end
  end

  defp effective_install_error(binary, nil) do
    "#{binary} installation completed, but the selected executable was not found"
  end

  defp effective_install_error(binary, path) do
    "#{binary} installation completed, but the selected executable is not usable at #{path}"
  end

  defp find_agent_browser_path do
    case resolve_agent_browser() do
      {:ok, path} -> path
      {:error, _reason} -> nil
    end
  end

  defp resolve_agent_browser do
    Binary.resolve(agent_browser_package_path())
  end

  defp ensure_agent_browser_installed(opts, force) do
    cond do
      configured_agent_browser_path?() ->
        case resolve_agent_browser() do
          {:ok, _path} -> :ok
          {:error, reason} -> {:error, reason}
        end

      force ->
        install(:agent_browser, opts)

      true ->
        case resolve_agent_browser() do
          {:ok, _path} -> :ok
          {:error, _reason} -> install(:agent_browser, opts)
        end
    end
  end

  defp configured_agent_browser_path? do
    configured_path(:agent_browser) not in [nil, ""]
  end

  defp find_vibium_path do
    case configured_path(:vibium) do
      path when is_binary(path) and path != "" ->
        if File.exists?(path), do: path, else: nil

      _ ->
        find_first_existing(vibium_binary_filenames(), &find_in_jido_browser_bin/1) ||
          find_vibium_from_npm() ||
          find_first_existing(vibium_binary_commands(), &find_in_path/1)
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

  defp find_lightpanda_path do
    case configured_path(:lightpanda) do
      path when is_binary(path) and path != "" ->
        if File.exists?(path), do: path, else: nil

      _ ->
        find_lightpanda_ex_path() || find_in_jido_browser_bin(lightpanda_binary_name()) || find_in_path("lightpanda")
    end
  end

  defp configured_path(:agent_browser) do
    :jido_browser
    |> Application.get_env(:agent_browser, [])
    |> Keyword.get(:binary_path)
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

  defp configured_path(:lightpanda) do
    :jido_browser
    |> Application.get_env(:lightpanda, [])
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
    case npm_global_root() do
      {:ok, npm_root} ->
        find_vibium_binary_in_dir(Path.join([npm_root, vibium_npm_package(), "bin"]))

      :error ->
        nil
    end
  end

  # Installation functions

  defp install_vibium(_opts) do
    case System.find_executable("npm") do
      nil ->
        {:error,
         "npm not found. Install Node.js first or install vibium manually from https://github.com/VibiumDev/vibium"}

      npm ->
        packages = vibium_npm_packages(configured_version(:vibium))
        Logger.info("Installing vibium via npm...")

        case run_npm_install(npm, packages) do
          {:ok, {_output, 0}} ->
            install_staged_vibium()

          {:ok, {output, code}} ->
            {:error, "npm install failed (exit #{code}): #{output}"}

          {:error, reason} ->
            {:error, "npm install failed: #{reason}"}
        end
    end
  end

  defp run_npm_install(npm, packages) do
    {:ok, System.cmd(npm, ["install", "-g" | packages], stderr_to_stdout: true)}
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp install_staged_vibium do
    with {:ok, staged, target} <- stage_vibium_binary() do
      result =
        with :ok <- run_vibium_chrome_install(staged) do
          promote_staged_binary(staged, target)
        end

      if result != :ok, do: remove_staged_binary(staged)
      result
    end
  end

  defp run_vibium_chrome_install(vibium) do
    Logger.info("Installing Chrome for Testing...")

    case System.cmd(vibium, ["install"], stderr_to_stdout: true) do
      {_output, 0} ->
        :ok

      {output, code} ->
        {:error, "vibium browser install failed (exit #{code}): #{output}"}
    end
  rescue
    error -> {:error, "vibium browser install failed: #{Exception.message(error)}"}
  end

  defp install_agent_browser(install_path, force) do
    target = Path.join(install_path, agent_browser_binary_name())

    case {force, Binary.validate(target, :package)} do
      {false, {:ok, _path}} ->
        Logger.info("agent-browser already installed at #{target}. Use --force to overwrite.")
        :ok

      _ ->
        download_and_install_agent_browser(install_path, target)
    end
  end

  defp download_and_install_agent_browser(install_path, target) do
    staged = staged_binary_path(target)
    url = agent_browser_download_url()
    Logger.info("Downloading agent-browser from #{url}...")

    result =
      with :ok <- ensure_install_directory(install_path),
           :ok <- prepare_staged_binary(staged),
           :ok <- download_binary(url, staged),
           {:ok, ^staged} <- Binary.validate(staged, :package),
           :ok <- run_agent_browser_install(staged) do
        promote_staged_binary(staged, target)
      end

    remove_staged_binary(staged)
    result
  end

  defp install_web(install_path, force) do
    target = Path.join(install_path, web_binary_name())

    if command_usable?(target, @command_probes.web) and not force do
      Logger.info("web already installed at #{target}. Use --force to overwrite.")
      :ok
    else
      staged = staged_binary_path(target)
      url = web_download_url()
      Logger.info("Downloading web from #{url}...")

      result =
        with :ok <- ensure_install_directory(install_path),
             :ok <- prepare_staged_binary(staged),
             :ok <- download_binary(url, staged),
             :ok <- ensure_command_usable(staged, @command_probes.web, "downloaded web binary") do
          promote_staged_binary(staged, target)
        end

      if result != :ok, do: remove_staged_binary(staged)
      result
    end
  end

  defp install_lightpanda(opts) do
    with {:ok, lightpanda_ex} <- ensure_lightpanda_ex() do
      with_lightpanda_ex_env(opts, fn ->
        lightpanda_ex
        |> call_lightpanda_ex(:bin_path, [])
        |> maybe_install_lightpanda(lightpanda_ex, opts[:force] || false)
      end)
    end
  end

  defp maybe_install_lightpanda(target, lightpanda_ex, force) do
    case {command_usable?(target, @command_probes.lightpanda), force} do
      {true, false} ->
        Logger.info("lightpanda already installed at #{target}. Use --force to overwrite.")
        :ok

      _ ->
        with :ok <- call_lightpanda_ex(lightpanda_ex, :install, []) do
          ensure_command_usable(target, @command_probes.lightpanda, "installed lightpanda binary")
        end
    end
  end

  defp with_lightpanda_ex_env(opts, fun) do
    old_version = Application.get_env(:lightpanda_ex, :version, :__missing__)
    old_path = Application.get_env(:lightpanda_ex, :path, :__missing__)

    Application.put_env(:lightpanda_ex, :version, configured_version(:lightpanda))

    if opts[:path] do
      Application.put_env(:lightpanda_ex, :path, Path.join(opts[:path], lightpanda_binary_name()))
    end

    try do
      fun.()
    after
      restore_env(:lightpanda_ex, :version, old_version)
      restore_env(:lightpanda_ex, :path, old_path)
    end
  end

  defp restore_env(app, key, :__missing__), do: Application.delete_env(app, key)
  defp restore_env(app, key, value), do: Application.put_env(app, key, value)

  defp web_binary_name do
    case target() do
      :windows_amd64 -> "web.exe"
      _ -> "web"
    end
  end

  defp lightpanda_binary_name do
    case target() do
      :windows_amd64 -> "lightpanda.exe"
      _ -> "lightpanda"
    end
  end

  defp agent_browser_binary_name do
    case target() do
      :darwin_arm64 -> "agent-browser-darwin-arm64"
      :darwin_amd64 -> "agent-browser-darwin-x64"
      :linux_amd64 -> "agent-browser-linux-x64"
      :linux_arm64 -> "agent-browser-linux-arm64"
      :windows_amd64 -> "agent-browser-win32-x64.exe"
    end
  end

  defp agent_browser_download_url do
    version = configured_version(:agent_browser)
    "https://github.com/vercel-labs/agent-browser/releases/download/v#{version}/#{agent_browser_binary_name()}"
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

  defp lightpanda_version do
    with {:module, lightpanda_ex} <- Code.ensure_loaded(LightpandaEx),
         true <- function_exported?(lightpanda_ex, :latest_version, 0) do
      call_lightpanda_ex(lightpanda_ex, :latest_version, [])
    else
      _ -> @lightpanda_version
    end
  rescue
    _ -> @lightpanda_version
  end

  defp ensure_lightpanda_ex do
    if Code.ensure_loaded?(LightpandaEx) do
      {:ok, LightpandaEx}
    else
      {:error, "lightpanda_ex optional dependency is required to install Lightpanda"}
    end
  end

  defp find_lightpanda_ex_path do
    if Code.ensure_loaded?(LightpandaEx) and function_exported?(LightpandaEx, :bin_path, 0) do
      path = call_lightpanda_ex(LightpandaEx, :bin_path, [])
      if File.exists?(path), do: path, else: nil
    end
  rescue
    _ -> nil
  end

  defp call_lightpanda_ex(module, function, args) do
    apply(module, function, args)
  end

  defp run_agent_browser_install(binary) do
    Logger.info("Installing browser runtime via agent-browser install...")

    case System.cmd(binary, ["install"], stderr_to_stdout: true) do
      {_output, 0} ->
        :ok

      {output, code} ->
        {:error, "agent-browser install failed (exit #{code}): #{output}"}
    end
  rescue
    error -> {:error, "agent-browser install failed: #{Exception.message(error)}"}
  end

  defp vibium_npm_packages(version) do
    ["vibium", vibium_npm_package()]
    |> Enum.map(&versioned_package(&1, version))
  end

  defp versioned_package(package, version) when is_binary(version) and version != "" do
    "#{package}@#{version}"
  end

  defp versioned_package(package, _version), do: package

  defp stage_vibium_binary do
    case find_vibium_from_npm() do
      nil ->
        {:error, "Could not stage vibium binary after npm install: installed command was not found"}

      source ->
        target_dir = default_install_path()
        target = Path.join(target_dir, Path.basename(source))
        staged = staged_binary_path(target)

        result =
          with :ok <- ensure_install_directory(target_dir),
               :ok <- prepare_staged_binary(staged),
               :ok <- copy_staged_binary(source, staged) do
            {:ok, staged, target}
          end

        if not match?({:ok, _staged, _target}, result), do: remove_staged_binary(staged)
        result
    end
  end

  defp copy_staged_binary(source, staged) do
    with :ok <- file_result(File.cp(source, staged), "copy vibium binary to #{staged}") do
      file_result(File.chmod(staged, 0o755), "make vibium binary executable at #{staged}")
    end
  end

  defp staged_binary_path(target) do
    case Path.extname(target) do
      "" -> target <> ".tmp"
      extension -> Path.rootname(target, extension) <> ".tmp" <> extension
    end
  end

  defp prepare_staged_binary(staged) do
    case File.rm(staged) do
      :ok -> :ok
      {:error, :enoent} -> :ok
      {:error, reason} -> {:error, file_error("remove old staged binary at #{staged}", reason)}
    end
  end

  defp promote_staged_binary(staged, target) do
    case File.rename(staged, target) do
      :ok ->
        :ok

      {:error, :eexist} ->
        with :ok <- file_result(File.cp(staged, target), "replace binary at #{target}") do
          file_result(File.rm(staged), "remove promoted staged binary at #{staged}")
        end

      {:error, reason} ->
        {:error, file_error("move staged binary to #{target}", reason)}
    end
  end

  defp remove_staged_binary(staged) do
    case File.rm(staged) do
      :ok -> :ok
      {:error, :enoent} -> :ok
      {:error, reason} -> Logger.warning(file_error("remove staged binary at #{staged}", reason))
    end
  end

  defp ensure_install_directory(path) do
    file_result(File.mkdir_p(path), "create install directory at #{path}")
  end

  defp ensure_command_usable(path, args, label) do
    if command_usable?(path, args) do
      :ok
    else
      {:error, "#{label} is not usable at #{path}"}
    end
  end

  defp file_result(:ok, _action), do: :ok
  defp file_result({:error, reason}, action), do: {:error, file_error(action, reason)}

  defp file_error(action, reason) do
    "Could not #{action}: #{reason |> :file.format_error() |> IO.chardata_to_string()}"
  end

  defp find_first_existing(candidates, finder) do
    Enum.find_value(candidates, finder)
  end

  defp find_vibium_binary_in_dir(dir) do
    find_first_existing(vibium_binary_filenames(), fn binary_name ->
      path = Path.join(dir, binary_name)
      if File.exists?(path), do: path, else: nil
    end)
  end

  defp npm_global_root do
    case System.cmd("npm", ["root", "-g"], stderr_to_stdout: true) do
      {npm_root, 0} -> {:ok, String.trim(npm_root)}
      _ -> :error
    end
  rescue
    _ -> :error
  end

  defp vibium_binary_commands, do: ["vibium", "clicker"]

  defp vibium_binary_filenames do
    case target() do
      :windows_amd64 -> ["vibium.exe", "clicker.exe", "vibium", "clicker"]
      _ -> vibium_binary_commands()
    end
  end

  defp download_binary(url, target) do
    case http_download(url) do
      {:ok, body} ->
        with :ok <- file_result(File.write(target, body), "write downloaded binary to #{target}"),
             :ok <- file_result(File.chmod(target, 0o755), "make downloaded binary executable at #{target}") do
          Logger.info("✓ Installed to #{target}")
          :ok
        end

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
