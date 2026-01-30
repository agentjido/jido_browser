defmodule JidoBrowser.Adapter do
  @moduledoc """
  Behaviour for browser automation adapters.

  Adapters implement the low-level browser control protocol, allowing
  JidoBrowser to work with different browser automation backends.

  ## Return Value Contract

  All operations (except `start_session` and `end_session`) return a consistent
  3-tuple on success:

      {:ok, session, result_map}

  This ensures:
  - Callers always receive the potentially-updated session
  - Consistent API regardless of whether the operation modifies state
  - Session can be threaded through operation chains

  ## Implementing an Adapter

      defmodule MyAdapter do
        @behaviour JidoBrowser.Adapter

        @impl true
        def start_session(opts) do
          # Start browser, return {:ok, session} or {:error, reason}
        end

        @impl true
        def end_session(session) do
          # Clean up resources, return :ok or {:error, reason}
        end

        @impl true
        def navigate(session, url, opts) do
          # Navigate and return session + result
          {:ok, updated_session, %{url: url}}
        end

        @impl true
        def screenshot(session, opts) do
          # Even read-only ops return the session for consistency
          {:ok, session, %{bytes: png_data, mime: "image/png"}}
        end

        # ... implement other callbacks
      end

  ## Optional Callbacks

  - `evaluate/3` - JavaScript evaluation (not all backends support this)

  ## Built-in Adapters

  - `JidoBrowser.Adapters.Vibium` - Uses Vibium Go binary (WebDriver BiDi)
  - `JidoBrowser.Adapters.Web` - Uses chrismccord/web CLI

  """

  alias JidoBrowser.Session

  @doc """
  Starts a new browser session.
  """
  @callback start_session(opts :: keyword()) :: {:ok, Session.t()} | {:error, term()}

  @doc """
  Ends a browser session and cleans up resources.
  """
  @callback end_session(session :: Session.t()) :: :ok | {:error, term()}

  @doc """
  Navigates to a URL.

  Returns the updated session with `current_url` set, plus a result map.
  """
  @callback navigate(session :: Session.t(), url :: String.t(), opts :: keyword()) ::
              {:ok, Session.t(), map()} | {:error, term()}

  @doc """
  Clicks an element matching the selector.

  Returns the updated session plus a result map.
  """
  @callback click(session :: Session.t(), selector :: String.t(), opts :: keyword()) ::
              {:ok, Session.t(), map()} | {:error, term()}

  @doc """
  Types text into an element matching the selector.

  Returns the updated session plus a result map.
  """
  @callback type(
              session :: Session.t(),
              selector :: String.t(),
              text :: String.t(),
              opts :: keyword()
            ) ::
              {:ok, Session.t(), map()} | {:error, term()}

  @doc """
  Takes a screenshot of the current page.
  """
  @callback screenshot(session :: Session.t(), opts :: keyword()) ::
              {:ok, Session.t(), %{bytes: binary(), mime: String.t()}} | {:error, term()}

  @doc """
  Extracts content from the current page.
  """
  @callback extract_content(session :: Session.t(), opts :: keyword()) ::
              {:ok, Session.t(), %{content: String.t(), format: atom()}} | {:error, term()}

  @doc """
  Executes JavaScript in the browser context.
  """
  @callback evaluate(session :: Session.t(), script :: String.t(), opts :: keyword()) ::
              {:ok, Session.t(), %{result: term()}} | {:error, term()}

  @optional_callbacks [evaluate: 3]
end
