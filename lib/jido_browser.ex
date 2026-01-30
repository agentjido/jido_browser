defmodule JidoBrowser do
  @moduledoc """
  Browser automation for Jido AI agents.

  JidoBrowser provides a set of Jido Actions for web browsing, enabling AI agents
  to navigate, interact with, and extract content from web pages.

  ## Architecture

  JidoBrowser uses an adapter pattern to support multiple browser automation backends:

  - `JidoBrowser.Adapters.Vibium` - Default adapter using Vibium (WebDriver BiDi)
  - `JidoBrowser.Adapters.Web` - Adapter using chrismccord/web CLI

  ## Quick Start

      # Start a browser session
      {:ok, session} = JidoBrowser.start_session()

      # Navigate to a page
      {:ok, _} = JidoBrowser.navigate(session, "https://example.com")

      # Click an element
      {:ok, _} = JidoBrowser.click(session, "button#submit")

      # Extract page content as markdown
      {:ok, content} = JidoBrowser.extract_content(session)

      # End session
      :ok = JidoBrowser.end_session(session)

  ## Configuration

      config :jido_browser,
        adapter: JidoBrowser.Adapters.Vibium,
        timeout: 30_000

  """

  alias JidoBrowser.Session

  @default_adapter JidoBrowser.Adapters.Vibium

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

  ## Examples

      {:ok, _} = JidoBrowser.navigate(session, "https://example.com")

  """
  @spec navigate(Session.t(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def navigate(%Session{} = session, url, opts \\ []) do
    session.adapter.navigate(session, url, opts)
  end

  @doc """
  Clicks an element matching the given selector.

  ## Examples

      {:ok, _} = JidoBrowser.click(session, "button#submit")
      {:ok, _} = JidoBrowser.click(session, "a.nav-link", text: "About")

  """
  @spec click(Session.t(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def click(%Session{} = session, selector, opts \\ []) do
    session.adapter.click(session, selector, opts)
  end

  @doc """
  Types text into an element matching the given selector.

  ## Examples

      {:ok, _} = JidoBrowser.type(session, "input#email", "user@example.com")

  """
  @spec type(Session.t(), String.t(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def type(%Session{} = session, selector, text, opts \\ []) do
    session.adapter.type(session, selector, text, opts)
  end

  @doc """
  Takes a screenshot of the current page.

  ## Options

    * `:full_page` - Capture the full scrollable page (default: `false`)
    * `:format` - Image format, `:png` or `:jpeg` (default: `:png`)

  ## Examples

      {:ok, %{bytes: png_data}} = JidoBrowser.screenshot(session)
      {:ok, %{bytes: jpeg_data}} = JidoBrowser.screenshot(session, format: :jpeg)

  """
  @spec screenshot(Session.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def screenshot(%Session{} = session, opts \\ []) do
    session.adapter.screenshot(session, opts)
  end

  @doc """
  Extracts the page content, optionally converting to markdown.

  ## Options

    * `:format` - Output format, `:html` or `:markdown` (default: `:markdown`)
    * `:selector` - CSS selector to scope extraction (default: `"body"`)

  ## Examples

      {:ok, %{content: markdown}} = JidoBrowser.extract_content(session)
      {:ok, %{content: html}} = JidoBrowser.extract_content(session, format: :html)

  """
  @spec extract_content(Session.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def extract_content(%Session{} = session, opts \\ []) do
    session.adapter.extract_content(session, opts)
  end

  @doc """
  Executes arbitrary JavaScript in the browser context.

  ## Examples

      {:ok, %{result: title}} = JidoBrowser.evaluate(session, "document.title")

  """
  @spec evaluate(Session.t(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def evaluate(%Session{} = session, script, opts \\ []) do
    session.adapter.evaluate(session, script, opts)
  end

  # Private helpers

  defp configured_adapter do
    Application.get_env(:jido_browser, :adapter, @default_adapter)
  end
end
