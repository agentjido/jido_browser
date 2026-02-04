defmodule JidoBrowser.Adapters.Vibium do
  @moduledoc """
  Vibium adapter for browser automation.

  Uses the Vibium clicker binary which provides:
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
        adapter: JidoBrowser.Adapters.Vibium,
        vibium: [
          binary_path: "/path/to/clicker",
          headless: true
        ]

  """

  @behaviour JidoBrowser.Adapter

  alias JidoBrowser.Error
  alias JidoBrowser.Session

  @default_timeout 30_000

  @impl true
  def start_session(opts \\ []) do
    headless = Keyword.get(opts, :headless, true)

    case find_clicker_binary() do
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
  def end_session(%Session{}) do
    :ok
  end

  @impl true
  def navigate(%Session{connection: connection} = session, url, opts) do
    timeout = opts[:timeout] || @default_timeout

    case run_clicker(connection, ["navigate", url], timeout) do
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

        case run_clicker(connection, args, timeout) do
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

        case run_clicker(connection, args, timeout) do
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

      with {:ok, _output} <- run_clicker(connection, args, timeout),
           {:ok, bytes} <- File.read(path) do
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

        case run_clicker(connection, args, timeout) do
          {:ok, content} ->
            {:ok, session, %{content: content, format: format}}

          {:error, reason} ->
            {:error, Error.adapter_error("Extract content failed", %{reason: reason})}
        end
    end
  end

  defp build_extract_args(url, selector, :html), do: ["find", url, selector, "--html"]
  defp build_extract_args(url, selector, :markdown), do: ["find", url, selector, "--markdown"]
  defp build_extract_args(url, selector, :text), do: ["find", url, selector]

  @impl true
  def evaluate(%Session{connection: connection} = session, script, opts) do
    case connection.current_url do
      nil ->
        {:error, Error.navigation_error(nil, :no_current_url)}

      url ->
        timeout = opts[:timeout] || @default_timeout
        args = ["eval", url, script]

        case run_clicker(connection, args, timeout) do
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

  # Private helpers

  defp run_clicker(%{binary: binary, headless: headless}, args, timeout) do
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
        {:error, "clicker exited with code #{code}: #{output}"}
    after
      timeout ->
        Port.close(port)
        {:error, "Command timed out after #{timeout}ms"}
    end
  end

  defp find_clicker_binary do
    case config(:binary_path) do
      path when is_binary(path) and path != "" ->
        if File.exists?(path), do: {:ok, path}, else: {:error, "Binary not found at #{path}"}

      _ ->
        case find_clicker_from_npm() do
          path when is_binary(path) -> {:ok, path}
          nil -> find_clicker_in_path()
        end
    end
  end

  defp find_clicker_in_path do
    case System.find_executable("clicker") do
      path when is_binary(path) ->
        {:ok, path}

      nil ->
        # Check jido_browser install path
        jido_path = Path.join(JidoBrowser.Installer.default_install_path(), "clicker")

        if File.exists?(jido_path) do
          {:ok, jido_path}
        else
          {:error, "Vibium clicker binary not found. Install with: mix jido_browser.install vibium"}
        end
    end
  end

  defp find_clicker_from_npm do
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
    case JidoBrowser.Installer.target() do
      :darwin_arm64 -> "@vibium/darwin-arm64"
      :darwin_amd64 -> "@vibium/darwin-x64"
      :linux_amd64 -> "@vibium/linux-x64"
      :linux_arm64 -> "@vibium/linux-arm64"
      :windows_amd64 -> "@vibium/win32-x64"
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
