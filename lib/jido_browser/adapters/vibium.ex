defmodule Jido.Browser.Adapters.Vibium do
  @moduledoc """
  Vibium adapter for browser automation.

  Uses the Vibium CLI binary which provides:
  - WebDriver BiDi protocol (standard-based)
  - Automatic Chrome download and management
  - Built-in MCP server support
  - ~10MB single binary

  ## Installation

  Install via mix task:

      mix jido_browser.install vibium

  Or manually:

      npm install -g vibium @vibium/darwin-arm64

  ## Configuration

      config :jido_browser,
        adapter: Jido.Browser.Adapters.Vibium,
        vibium: [
          binary_path: "/path/to/vibium",
          headless: true
        ]

  """

  @behaviour Jido.Browser.Adapter

  alias Jido.Browser.Error
  alias Jido.Browser.Installer
  alias Jido.Browser.Session

  @default_timeout 30_000

  @impl true
  def start_session(opts \\ []) do
    headless = Keyword.get(opts, :headless, true)

    case find_vibium_binary() do
      {:ok, binary} ->
        Session.new(%{
          adapter: __MODULE__,
          connection: %{binary: binary, headless: headless, current_url: nil},
          opts: Map.new(opts)
        })

      {:error, reason} ->
        {:error, Error.adapter_error("Failed to start Vibium session", %{reason: reason})}
    end
  end

  @impl true
  def end_session(%Session{connection: %{binary: binary, headless: headless}}) do
    _ = reset_vibium_session(binary, headless)
    :ok
  end

  @impl true
  def navigate(%Session{connection: connection} = session, url, opts) do
    timeout = opts[:timeout] || @default_timeout

    case run_vibium(connection, ["go", url], timeout) do
      {:ok, output} ->
        updated_connection = Map.put(connection, :current_url, url)
        updated_session = %{session | connection: updated_connection}
        {:ok, updated_session, %{url: url, output: output}}

      {:error, reason} ->
        {:error, Error.navigation_error(url, reason)}
    end
  end

  @impl true
  def click(%Session{connection: connection} = session, selector, opts) do
    case connection.current_url do
      nil ->
        {:error, Error.navigation_error(nil, :no_current_url)}

      url ->
        timeout = opts[:timeout] || @default_timeout
        args = ["click", url, selector]

        case run_vibium(connection, args, timeout) do
          {:ok, output} ->
            {:ok, session, %{selector: selector, output: output}}

          {:error, reason} ->
            {:error, Error.element_error("click", selector, reason)}
        end
    end
  end

  @impl true
  def type(%Session{connection: connection} = session, selector, text, opts) do
    case connection.current_url do
      nil ->
        {:error, Error.navigation_error(nil, :no_current_url)}

      url ->
        timeout = opts[:timeout] || @default_timeout
        args = ["type", url, selector, text]

        case run_vibium(connection, args, timeout) do
          {:ok, output} ->
            {:ok, session, %{selector: selector, output: output}}

          {:error, reason} ->
            {:error, Error.element_error("type", selector, reason)}
        end
    end
  end

  @impl true
  def screenshot(%Session{connection: connection} = session, opts) do
    case connection.current_url do
      nil ->
        {:error, Error.navigation_error(nil, :no_current_url)}

      url ->
        format = opts[:format] || :png

        case validate_screenshot_format(format) do
          :ok -> take_png_screenshot(session, connection, url, opts)
          {:error, _} = error -> error
        end
    end
  end

  defp validate_screenshot_format(:png), do: :ok

  defp validate_screenshot_format(:jpeg) do
    {:error,
     Error.adapter_error("Vibium adapter only supports PNG screenshots", %{
       requested_format: :jpeg,
       supported_formats: [:png]
     })}
  end

  defp validate_screenshot_format(other) do
    {:error,
     Error.adapter_error("Unsupported screenshot format", %{
       requested_format: other,
       supported_formats: [:png]
     })}
  end

  defp take_png_screenshot(session, connection, url, opts) do
    timeout = opts[:timeout] || @default_timeout
    full_page = opts[:full_page] || false

    with_tmp_file("jido_browser_screenshot", ".png", fn path ->
      args = build_screenshot_args(url, path, full_page)

      with {:ok, output} <- run_vibium(connection, args, timeout),
           {:ok, bytes} <- read_screenshot_bytes(output, path) do
        {:ok, session, %{bytes: bytes, mime: "image/png", format: :png}}
      else
        {:error, reason} when is_atom(reason) ->
          {:error, Error.adapter_error("Failed to read screenshot", %{reason: reason})}

        {:error, reason} ->
          {:error, Error.adapter_error("Screenshot failed", %{reason: reason})}
      end
    end)
  end

  defp build_screenshot_args(url, path, full_page) do
    args = ["screenshot", url, "--output", path]
    if full_page, do: args ++ ["--full-page"], else: args
  end

  defp read_screenshot_bytes(output, requested_path) do
    actual_path = extract_screenshot_path(output) || requested_path
    result = File.read(actual_path)

    if actual_path != requested_path do
      File.rm(actual_path)
    end

    result
  end

  defp extract_screenshot_path(output) do
    case Regex.run(~r/Screenshot saved to (.+)$/, output, capture: :all_but_first) do
      [path] -> String.trim(path)
      _ -> nil
    end
  end

  @impl true
  def extract_content(%Session{connection: connection} = session, opts) do
    case connection.current_url do
      nil ->
        {:error, Error.navigation_error(nil, :no_current_url)}

      url ->
        timeout = opts[:timeout] || @default_timeout
        selector = opts[:selector] || "body"
        format = opts[:format] || :markdown
        args = build_extract_args(url, selector, format)

        case run_vibium(connection, args, timeout) do
          {:ok, content} ->
            {:ok, session, %{content: content, format: format}}

          {:error, reason} ->
            {:error, Error.adapter_error("Extract content failed", %{reason: reason})}
        end
    end
  end

  defp build_extract_args(url, selector, :html), do: build_extract_command("html", url, selector)

  # Vibium no longer exposes markdown output, so plain text is the closest stable fallback.
  defp build_extract_args(url, selector, :markdown), do: build_extract_command("text", url, selector)
  defp build_extract_args(url, selector, :text), do: build_extract_command("text", url, selector)

  defp build_extract_command(command, url, selector) when selector in [nil, "", "body"] do
    [command, url]
  end

  defp build_extract_command(command, url, selector), do: [command, url, selector]

  @impl true
  def evaluate(%Session{connection: connection} = session, script, opts) do
    case connection.current_url do
      nil ->
        {:error, Error.navigation_error(nil, :no_current_url)}

      url ->
        timeout = opts[:timeout] || @default_timeout
        args = ["eval", url, script]

        case run_vibium(connection, args, timeout) do
          {:ok, result} ->
            parsed_result = parse_js_result(result)
            {:ok, session, %{result: parsed_result}}

          {:error, reason} ->
            {:error, Error.adapter_error("Evaluate failed", %{reason: reason})}
        end
    end
  end

  @spec parse_js_result(binary()) :: term()
  defp parse_js_result(result) do
    case Jason.decode(result) do
      {:ok, decoded} -> decoded
      {:error, _} -> result
    end
  end

  defp run_vibium(%{binary: binary, headless: headless}, args, timeout) do
    full_args = if headless, do: ["--headless" | args], else: args

    port =
      Port.open({:spawn_executable, binary}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        args: full_args
      ])

    collect_output(port, [], timeout)
  end

  # Use iodata accumulation for O(n) performance instead of O(n²) string concat
  defp collect_output(port, acc, timeout) do
    receive do
      {^port, {:data, data}} ->
        collect_output(port, [acc | [data]], timeout)

      {^port, {:exit_status, 0}} ->
        {:ok, acc |> IO.iodata_to_binary() |> String.trim()}

      {^port, {:exit_status, code}} ->
        output = IO.iodata_to_binary(acc)
        {:error, "vibium exited with code #{code}: #{output}"}
    after
      timeout ->
        Port.close(port)
        {:error, "Command timed out after #{timeout}ms"}
    end
  end

  defp find_vibium_binary do
    case config(:binary_path) do
      path when is_binary(path) and path != "" ->
        if File.exists?(path), do: {:ok, path}, else: {:error, "Binary not found at #{path}"}

      _ ->
        case find_vibium_from_install_path() || find_vibium_from_npm() do
          path when is_binary(path) -> {:ok, path}
          nil -> find_vibium_in_path()
        end
    end
  end

  defp find_vibium_in_path do
    case find_first_existing(vibium_binary_commands(), &System.find_executable/1) do
      path when is_binary(path) ->
        {:ok, path}

      nil ->
        {:error, "Vibium binary not found. Install with: mix jido_browser.install vibium"}
    end
  end

  defp find_vibium_from_install_path do
    find_first_existing(vibium_binary_filenames(), fn binary_name ->
      path = Path.join(Installer.default_install_path(), binary_name)
      if File.exists?(path), do: path, else: nil
    end)
  end

  defp find_vibium_from_npm do
    case npm_global_root() do
      {:ok, npm_root} ->
        find_vibium_binary_in_dir(Path.join([npm_root, vibium_platform_package(), "bin"]))

      :error ->
        nil
    end
  end

  defp vibium_platform_package do
    case Installer.target() do
      :darwin_arm64 -> "@vibium/darwin-arm64"
      :darwin_amd64 -> "@vibium/darwin-x64"
      :linux_amd64 -> "@vibium/linux-x64"
      :linux_arm64 -> "@vibium/linux-arm64"
      :windows_amd64 -> "@vibium/win32-x64"
    end
  end

  defp vibium_binary_commands, do: ["vibium", "clicker"]

  defp vibium_binary_filenames do
    case Installer.target() do
      :windows_amd64 -> ["vibium.exe", "clicker.exe", "vibium", "clicker"]
      _ -> vibium_binary_commands()
    end
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

  defp reset_vibium_session(binary, headless) do
    case run_vibium(%{binary: binary, headless: headless}, ["stop"], 5_000) do
      {:ok, _} -> :ok
      {:error, _} -> :ok
    end
  end

  defp config(key, default \\ nil) do
    :jido_browser
    |> Application.get_env(:vibium, [])
    |> Keyword.get(key, default)
  end

  # Execute function with a temp file, ensuring cleanup even on errors
  defp with_tmp_file(prefix, suffix, fun) do
    path = Path.join(System.tmp_dir!(), "#{prefix}_#{System.unique_integer()}#{suffix}")

    try do
      fun.(path)
    after
      File.rm(path)
    end
  end
end
