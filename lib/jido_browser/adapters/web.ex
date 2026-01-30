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

  alias JidoBrowser.Session
  alias JidoBrowser.Error

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
  def navigate(%Session{} = session, url, opts) do
    timeout = opts[:timeout] || @default_timeout

    case run_web_command([url], timeout: timeout, profile: session.connection.profile) do
      {:ok, output} ->
        {:ok, %{url: url, content: output}}

      {:error, reason} ->
        {:error, Error.navigation_error(url, reason)}
    end
  end

  @impl true
  def click(%Session{} = session, selector, opts) do
    url = session.connection.current_url || raise "No current URL - navigate first"
    timeout = opts[:timeout] || @default_timeout

    args = [url, "--click", selector]
    args = if opts[:text], do: args ++ ["--text", opts[:text]], else: args

    case run_web_command(args, timeout: timeout, profile: session.connection.profile) do
      {:ok, output} ->
        {:ok, %{selector: selector, content: output}}

      {:error, reason} ->
        {:error, Error.element_error("click", selector, reason)}
    end
  end

  @impl true
  def type(%Session{} = session, selector, text, opts) do
    url = session.connection.current_url || raise "No current URL - navigate first"
    timeout = opts[:timeout] || @default_timeout

    args = [url, "--fill", "#{selector}=#{text}"]

    case run_web_command(args, timeout: timeout, profile: session.connection.profile) do
      {:ok, output} ->
        {:ok, %{selector: selector, content: output}}

      {:error, reason} ->
        {:error, Error.element_error("type", selector, reason)}
    end
  end

  @impl true
  def screenshot(%Session{} = session, opts) do
    url = session.connection.current_url || raise "No current URL - navigate first"
    timeout = opts[:timeout] || @default_timeout

    # Create temp file for screenshot
    path = Path.join(System.tmp_dir!(), "jido_browser_#{System.unique_integer()}.png")

    args = [url, "--screenshot", path]

    case run_web_command(args, timeout: timeout, profile: session.connection.profile) do
      {:ok, _output} ->
        case File.read(path) do
          {:ok, bytes} ->
            File.rm(path)
            {:ok, %{bytes: bytes, mime: "image/png"}}

          {:error, reason} ->
            {:error, Error.adapter_error("Failed to read screenshot", %{reason: reason})}
        end

      {:error, reason} ->
        {:error, Error.adapter_error("Screenshot failed", %{reason: reason})}
    end
  end

  @impl true
  def extract_content(%Session{} = session, opts) do
    url = session.connection.current_url || raise "No current URL - navigate first"
    timeout = opts[:timeout] || @default_timeout

    # web CLI returns markdown by default
    case run_web_command([url], timeout: timeout, profile: session.connection.profile) do
      {:ok, content} ->
        {:ok, %{content: content, format: :markdown}}

      {:error, reason} ->
        {:error, Error.adapter_error("Extract content failed", %{reason: reason})}
    end
  end

  @impl true
  def evaluate(%Session{} = session, script, opts) do
    url = session.connection.current_url || raise "No current URL - navigate first"
    timeout = opts[:timeout] || @default_timeout

    args = [url, "--js", script]

    case run_web_command(args, timeout: timeout, profile: session.connection.profile) do
      {:ok, output} ->
        {:ok, %{result: output}}

      {:error, reason} ->
        {:error, Error.adapter_error("Evaluate failed", %{reason: reason})}
    end
  end

  # Private helpers

  defp run_web_command(args, opts) do
    binary = find_web_binary()
    timeout = opts[:timeout] || @default_timeout
    profile = opts[:profile]

    full_args = if profile, do: ["--profile", profile | args], else: args

    case System.cmd(binary, full_args, stderr_to_stdout: true, timeout: timeout) do
      {output, 0} -> {:ok, String.trim(output)}
      {output, code} -> {:error, "web exited with code #{code}: #{output}"}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp find_web_binary do
    config(:binary_path) ||
      System.find_executable("web") ||
      raise "web binary not found. Install from: https://github.com/chrismccord/web"
  end

  defp config(key, default \\ nil) do
    :jido_browser
    |> Application.get_env(:web, [])
    |> Keyword.get(key, default)
  end
end
