defmodule JidoBrowser.Adapters.Web do
  @moduledoc """
  Adapter using chrismccord/web CLI.

  This adapter uses the `web` command-line tool which provides:
  - Firefox-based automation via Selenium
  - Built-in HTML to Markdown conversion
  - Phoenix LiveView-aware navigation
  - Session persistence with profiles

  ## Installation

  Download from https://github.com/chrismccord/web or build from source:

      git clone https://github.com/chrismccord/web
      cd web && make

  ## Configuration

      config :jido_browser,
        adapter: JidoBrowser.Adapters.Web,
        web: [
          binary_path: "/usr/local/bin/web",
          profile: "default"
        ]

  ## Notes

  This adapter is best suited for:
  - Scraping content as markdown for LLM consumption
  - Phoenix LiveView applications
  - Scenarios where Firefox is preferred over Chrome

  """

  @behaviour JidoBrowser.Adapter

  alias JidoBrowser.Error
  alias JidoBrowser.Session

  @default_timeout 30_000

  @impl true
  def start_session(opts \\ []) do
    profile = opts[:profile] || config(:profile, "default")

    Session.new(%{
      adapter: __MODULE__,
      connection: %{profile: profile, current_url: nil},
      opts: Map.new(opts)
    })
  end

  @impl true
  def end_session(%Session{}) do
    # web CLI is stateless between invocations (uses profile for persistence)
    :ok
  end

  @impl true
  def navigate(%Session{connection: connection} = session, url, opts) do
    timeout = opts[:timeout] || @default_timeout

    case run_web_command([url], timeout: timeout, profile: connection.profile) do
      {:ok, output} ->
        updated_connection = Map.put(connection, :current_url, url)
        updated_session = %{session | connection: updated_connection}
        {:ok, updated_session, %{url: url, content: output}}

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
        args = [url, "--click", selector]
        args = if opts[:text], do: args ++ ["--text", opts[:text]], else: args

        case run_web_command(args, timeout: timeout, profile: connection.profile) do
          {:ok, output} ->
            {:ok, session, %{selector: selector, content: output}}

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
        args = [url, "--fill", "#{selector}=#{text}"]

        case run_web_command(args, timeout: timeout, profile: connection.profile) do
          {:ok, output} ->
            {:ok, session, %{selector: selector, content: output}}

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
     Error.adapter_error("Web adapter only supports PNG screenshots", %{
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

      with {:ok, _output} <- run_web_command(args, timeout: timeout, profile: connection.profile),
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
    args = [url, "--screenshot", path]
    if full_page, do: args ++ ["--full-page"], else: args
  end

  @impl true
  def extract_content(%Session{connection: connection} = session, opts) do
    case connection.current_url do
      nil ->
        {:error, Error.navigation_error(nil, :no_current_url)}

      url ->
        timeout = opts[:timeout] || @default_timeout
        format = opts[:format] || :markdown
        # Note: Web adapter does not support :selector option - it extracts full page
        # The facade documents this limitation
        args = build_extract_args(url, format)

        case run_web_command(args, timeout: timeout, profile: connection.profile) do
          {:ok, content} ->
            {:ok, session, %{content: content, format: format}}

          {:error, reason} ->
            {:error, Error.adapter_error("Extract content failed", %{reason: reason})}
        end
    end
  end

  defp build_extract_args(url, :html), do: [url, "--html"]
  defp build_extract_args(url, :text), do: [url, "--text"]
  defp build_extract_args(url, :markdown), do: [url]

  @impl true
  def evaluate(%Session{connection: connection} = session, script, opts) do
    case connection.current_url do
      nil ->
        {:error, Error.navigation_error(nil, :no_current_url)}

      url ->
        timeout = opts[:timeout] || @default_timeout
        args = [url, "--js", script]

        case run_web_command(args, timeout: timeout, profile: connection.profile) do
          {:ok, output} ->
            parsed_result = parse_js_result(output)
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

  @spec run_web_command(list(), keyword()) :: {:ok, String.t()} | {:error, String.t()}
  defp run_web_command(args, opts) do
    case find_web_binary() do
      {:ok, binary} ->
        timeout = opts[:timeout] || @default_timeout
        profile = opts[:profile]

        full_args = if profile, do: ["--profile", profile | args], else: args

        try do
          run_with_timeout(binary, full_args, timeout)
        rescue
          e -> {:error, Exception.message(e)}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp run_with_timeout(binary, args, timeout) do
    port =
      Port.open({:spawn_executable, binary}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        args: args
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
        {:error, "web exited with code #{code}: #{output}"}
    after
      timeout ->
        Port.close(port)
        {:error, "Command timed out after #{timeout}ms"}
    end
  end

  @spec find_web_binary() :: {:ok, String.t()} | {:error, String.t()}
  defp find_web_binary do
    case config(:binary_path) do
      path when is_binary(path) and path != "" ->
        {:ok, path}

      _ ->
        find_web_in_path_or_install()
    end
  end

  defp find_web_in_path_or_install do
    case System.find_executable("web") do
      path when is_binary(path) ->
        {:ok, path}

      nil ->
        jido_path = Path.join(JidoBrowser.Installer.default_install_path(), "web")

        if File.exists?(jido_path) do
          {:ok, jido_path}
        else
          {:error, "web binary not found. Install with: mix jido_browser.install web"}
        end
    end
  end

  defp config(key, default \\ nil) do
    :jido_browser
    |> Application.get_env(:web, [])
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
