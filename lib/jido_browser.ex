defmodule JidoBrowser do
  @moduledoc """
  Browser automation for Jido AI agents.

  JidoBrowser provides a set of Jido Actions for web browsing, enabling AI agents
  to navigate, interact with, and extract content from web pages.

  ## Architecture

  JidoBrowser uses an adapter pattern to support multiple browser automation backends:

  - `JidoBrowser.Adapters.Vibium` - Default adapter using Vibium (WebDriver BiDi)
  - `JidoBrowser.Adapters.Web` - Adapter using chrismccord/web CLI

  ## Session State Pattern

  All operations return an updated session to ensure state changes are captured:

      {:ok, session, result} = JidoBrowser.navigate(session, "https://example.com")
      {:ok, session, result} = JidoBrowser.click(session, "button#submit")

  Always use the returned session for subsequent operations to ensure state
  (like `current_url`) is properly tracked.

  ## Quick Start

      # Start a browser session
      {:ok, session} = JidoBrowser.start_session()

      # Navigate to a page
      {:ok, session, _} = JidoBrowser.navigate(session, "https://example.com")

      # Click an element (use updated session from navigate)
      {:ok, session, _} = JidoBrowser.click(session, "button#submit")

      # Extract page content as markdown
      {:ok, _session, content} = JidoBrowser.extract_content(session)

      # End session
      :ok = JidoBrowser.end_session(session)

  ## Configuration

      config :jido_browser,
        adapter: JidoBrowser.Adapters.Vibium

  """

  alias JidoBrowser.Error
  alias JidoBrowser.Session

  @default_adapter JidoBrowser.Adapters.Vibium
  @default_timeout 30_000
  @supported_screenshot_formats [:png]
  @supported_extract_formats [:markdown, :html, :text]

  @doc """
  Starts a new browser session.

  ## Options

    * `:adapter` - The adapter module to use (default: `JidoBrowser.Adapters.Vibium`)
    * `:headless` - Whether to run in headless mode (default: `true`)
    * `:timeout` - Default timeout for operations in milliseconds (default: `30_000`)

  ## Examples

      {:ok, session} = JidoBrowser.start_session()
      {:ok, session} = JidoBrowser.start_session(headless: false)

  """
  @spec start_session(keyword()) :: {:ok, Session.t()} | {:error, term()}
  def start_session(opts \\ []) do
    adapter = opts[:adapter] || configured_adapter()
    adapter.start_session(opts)
  end

  @doc """
  Ends a browser session and cleans up resources.
  """
  @spec end_session(Session.t()) :: :ok | {:error, term()}
  def end_session(%Session{} = session) do
    session.adapter.end_session(session)
  end

  @doc """
  Navigates to a URL.

  Returns the updated session with `current_url` set.

  ## Examples

      {:ok, session, _} = JidoBrowser.navigate(session, "https://example.com")

  """
  @spec navigate(Session.t(), String.t(), keyword()) ::
          {:ok, Session.t(), map()} | {:error, term()}
  def navigate(session, url, opts \\ [])

  def navigate(%Session{}, url, _opts) when url in [nil, ""] do
    {:error, Error.invalid_error("URL cannot be nil or empty", %{url: url})}
  end

  def navigate(%Session{} = session, url, opts) do
    opts = normalize_timeout(opts)
    session.adapter.navigate(session, url, opts)
  end

  @doc """
  Clicks an element matching the given selector.

  ## Examples

      {:ok, session, _} = JidoBrowser.click(session, "button#submit")
      {:ok, session, _} = JidoBrowser.click(session, "a.nav-link", text: "About")

  """
  @spec click(Session.t(), String.t(), keyword()) ::
          {:ok, Session.t(), map()} | {:error, term()}
  def click(session, selector, opts \\ [])

  def click(%Session{}, selector, _opts) when selector in [nil, ""] do
    {:error, Error.invalid_error("Selector cannot be nil or empty", %{selector: selector})}
  end

  def click(%Session{} = session, selector, opts) do
    opts = normalize_timeout(opts)
    session.adapter.click(session, selector, opts)
  end

  @doc """
  Types text into an element matching the given selector.

  ## Examples

      {:ok, session, _} = JidoBrowser.type(session, "input#email", "user@example.com")

  """
  @spec type(Session.t(), String.t(), String.t(), keyword()) ::
          {:ok, Session.t(), map()} | {:error, term()}
  def type(session, selector, text, opts \\ [])

  def type(%Session{}, selector, _text, _opts) when selector in [nil, ""] do
    {:error, Error.invalid_error("Selector cannot be nil or empty", %{selector: selector})}
  end

  def type(%Session{} = session, selector, text, opts) do
    opts = normalize_timeout(opts)
    session.adapter.type(session, selector, text, opts)
  end

  @doc """
  Takes a screenshot of the current page.

  ## Options

    * `:full_page` - Capture the full scrollable page (default: `false`)
    * `:format` - Image format: `:png` (default: `:png`)

  Note: Currently only PNG format is supported by all adapters.

  ## Examples

      {:ok, _session, %{bytes: png_data}} = JidoBrowser.screenshot(session)
      {:ok, _session, %{bytes: png_data}} = JidoBrowser.screenshot(session, full_page: true)

  """
  @spec screenshot(Session.t(), keyword()) :: {:ok, Session.t(), map()} | {:error, term()}
  def screenshot(%Session{} = session, opts \\ []) do
    format = opts[:format] || :png

    if format in @supported_screenshot_formats do
      opts = normalize_timeout(opts)
      session.adapter.screenshot(session, opts)
    else
      {:error,
       Error.invalid_error("Unsupported screenshot format: #{inspect(format)}", %{
         format: format,
         supported: @supported_screenshot_formats
       })}
    end
  end

  @doc """
  Extracts the page content, optionally converting to markdown.

  ## Options

    * `:format` - Output format: `:markdown`, `:html`, or `:text` (default: `:markdown`)
    * `:selector` - CSS selector to scope extraction (default: `"body"`)

  Note: The `:selector` option is only supported by the Vibium adapter.
  The Web adapter will ignore this option.

  ## Examples

      {:ok, _session, %{content: markdown}} = JidoBrowser.extract_content(session)
      {:ok, _session, %{content: html}} = JidoBrowser.extract_content(session, format: :html)

  """
  @spec extract_content(Session.t(), keyword()) ::
          {:ok, Session.t(), map()} | {:error, term()}
  def extract_content(%Session{} = session, opts \\ []) do
    format = opts[:format] || :markdown

    if format in @supported_extract_formats do
      # Normalize defaults at facade level for consistency across adapters
      opts =
        opts
        |> Keyword.put_new(:format, :markdown)
        |> Keyword.put_new(:selector, "body")
        |> normalize_timeout()

      session.adapter.extract_content(session, opts)
    else
      {:error,
       Error.invalid_error("Unsupported extract format: #{inspect(format)}", %{
         format: format,
         supported: @supported_extract_formats
       })}
    end
  end

  @doc """
  Executes arbitrary JavaScript in the browser context.

  Note: This is an optional capability. Not all adapters support JavaScript
  evaluation. If unsupported, returns `{:error, Error.InvalidError}`.

  ## Examples

      {:ok, _session, %{result: title}} = JidoBrowser.evaluate(session, "document.title")

  """
  @spec evaluate(Session.t(), String.t(), keyword()) ::
          {:ok, Session.t(), map()} | {:error, term()}
  def evaluate(session, script, opts \\ [])

  def evaluate(%Session{}, script, _opts) when script in [nil, ""] do
    {:error, Error.invalid_error("Script cannot be nil or empty", %{script: script})}
  end

  def evaluate(%Session{adapter: adapter} = session, script, opts) do
    if function_exported?(adapter, :evaluate, 3) do
      opts = normalize_timeout(opts)
      adapter.evaluate(session, script, opts)
    else
      {:error,
       Error.invalid_error(
         "Adapter #{inspect(adapter)} does not support JavaScript evaluation",
         %{adapter: adapter}
       )}
    end
  end

  # Private helpers

  defp configured_adapter do
    Application.get_env(:jido_browser, :adapter, @default_adapter)
  end

  defp normalize_timeout(opts) do
    Keyword.put_new(opts, :timeout, @default_timeout)
  end
end
