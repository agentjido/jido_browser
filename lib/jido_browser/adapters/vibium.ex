defmodule JidoBrowser.Adapters.Vibium do
  @moduledoc """
  Vibium adapter for browser automation.

  Uses the Vibium Go binary which provides:
  - WebDriver BiDi protocol (standard-based)
  - Automatic Chrome download and management
  - Built-in MCP server support
  - ~10MB single binary

  ## Installation

  The Vibium binary is automatically downloaded on first use.
  You can also install it manually:

      npm install -g vibium

  ## Configuration

      config :jido_browser,
        adapter: JidoBrowser.Adapters.Vibium,
        vibium: [
          binary_path: "/usr/local/bin/vibium",
          port: 9515
        ]

  """

  @behaviour JidoBrowser.Adapter

  alias JidoBrowser.Session
  alias JidoBrowser.Error

  @default_port 9515
  @default_timeout 30_000

  @impl true
  def start_session(opts \\ []) do
    port = opts[:port] || config(:port, @default_port)
    headless = Keyword.get(opts, :headless, true)

    case ensure_vibium_running(port, headless) do
      {:ok, connection} ->
        Session.new(%{
          adapter: __MODULE__,
          connection: connection,
          opts: Map.new(opts)
        })

      {:error, reason} ->
        {:error, Error.adapter_error("Failed to start Vibium session", %{reason: reason})}
    end
  end

  @impl true
  def end_session(%Session{connection: connection}) do
    case send_command(connection, "browser_quit", %{}) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, Error.adapter_error("Failed to quit browser", %{reason: reason})}
    end
  end

  @impl true
  def navigate(%Session{connection: connection}, url, _opts) do
    case send_command(connection, "browser_navigate", %{url: url}) do
      {:ok, result} -> {:ok, %{url: url, result: result}}
      {:error, reason} -> {:error, Error.navigation_error(url, reason)}
    end
  end

  @impl true
  def click(%Session{connection: connection}, selector, opts) do
    params = %{selector: selector}
    params = if opts[:text], do: Map.put(params, :text, opts[:text]), else: params

    case send_command(connection, "browser_click", params) do
      {:ok, result} -> {:ok, %{selector: selector, result: result}}
      {:error, reason} -> {:error, Error.element_error("click", selector, reason)}
    end
  end

  @impl true
  def type(%Session{connection: connection}, selector, text, _opts) do
    case send_command(connection, "browser_type", %{selector: selector, text: text}) do
      {:ok, result} -> {:ok, %{selector: selector, result: result}}
      {:error, reason} -> {:error, Error.element_error("type", selector, reason)}
    end
  end

  @impl true
  def screenshot(%Session{connection: connection}, opts) do
    params = %{}
    params = if opts[:full_page], do: Map.put(params, :full_page, true), else: params

    case send_command(connection, "browser_screenshot", params) do
      {:ok, %{"data" => base64_data}} ->
        {:ok, %{bytes: Base.decode64!(base64_data), mime: "image/png"}}

      {:ok, result} ->
        {:ok, %{bytes: result, mime: "image/png"}}

      {:error, reason} ->
        {:error, Error.adapter_error("Screenshot failed", %{reason: reason})}
    end
  end

  @impl true
  def extract_content(%Session{connection: connection}, opts) do
    selector = opts[:selector] || "body"
    format = opts[:format] || :markdown

    # Vibium returns markdown by default
    case send_command(connection, "browser_find", %{selector: selector}) do
      {:ok, %{"text" => content}} ->
        {:ok, %{content: content, format: format}}

      {:ok, result} when is_binary(result) ->
        {:ok, %{content: result, format: format}}

      {:error, reason} ->
        {:error, Error.element_error("extract", selector, reason)}
    end
  end

  @impl true
  def evaluate(%Session{connection: connection}, script, _opts) do
    # Note: Vibium may not support arbitrary JS evaluation
    # This is a placeholder for when/if that feature is added
    case send_command(connection, "browser_evaluate", %{script: script}) do
      {:ok, result} -> {:ok, %{result: result}}
      {:error, reason} -> {:error, Error.adapter_error("Evaluate failed", %{reason: reason})}
    end
  end

  # Private helpers

  defp ensure_vibium_running(port, headless) do
    base_url = "http://localhost:#{port}"

    case check_vibium_health(base_url) do
      :ok ->
        {:ok, %{base_url: base_url, port: port}}

      :not_running ->
        start_vibium_process(port, headless)
    end
  end

  defp check_vibium_health(base_url) do
    case Req.get("#{base_url}/health", receive_timeout: 1_000) do
      {:ok, %{status: 200}} -> :ok
      _ -> :not_running
    end
  rescue
    _ -> :not_running
  end

  defp start_vibium_process(port, headless) do
    binary = find_vibium_binary()

    args = ["--port", to_string(port)]
    args = if headless, do: args ++ ["--headless"], else: args

    case System.cmd(binary, args ++ ["--background"], stderr_to_stdout: true) do
      {_, 0} ->
        # Wait for Vibium to be ready
        wait_for_vibium("http://localhost:#{port}", 10)

      {output, code} ->
        {:error, "Vibium exited with code #{code}: #{output}"}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp wait_for_vibium(_base_url, 0), do: {:error, "Vibium failed to start"}

  defp wait_for_vibium(base_url, retries) do
    case check_vibium_health(base_url) do
      :ok -> {:ok, %{base_url: base_url}}
      :not_running ->
        Process.sleep(500)
        wait_for_vibium(base_url, retries - 1)
    end
  end

  defp find_vibium_binary do
    config(:binary_path) ||
      System.find_executable("vibium") ||
      System.find_executable("npx") |> vibium_via_npx() ||
      raise "Vibium binary not found. Install with: npm install -g vibium"
  end

  defp vibium_via_npx(nil), do: nil
  defp vibium_via_npx(_npx), do: "npx"

  defp send_command(%{base_url: base_url}, method, params) do
    url = "#{base_url}/mcp"

    body = %{
      jsonrpc: "2.0",
      id: System.unique_integer([:positive]),
      method: "tools/call",
      params: %{
        name: method,
        arguments: params
      }
    }

    case Req.post(url, json: body, receive_timeout: @default_timeout) do
      {:ok, %{status: 200, body: %{"result" => result}}} ->
        {:ok, result}

      {:ok, %{status: 200, body: %{"error" => error}}} ->
        {:error, error}

      {:ok, %{status: status, body: body}} ->
        {:error, "HTTP #{status}: #{inspect(body)}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp config(key, default \\ nil) do
    :jido_browser
    |> Application.get_env(:vibium, [])
    |> Keyword.get(key, default)
  end
end
