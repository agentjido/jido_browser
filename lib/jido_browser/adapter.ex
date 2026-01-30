defmodule JidoBrowser.Adapter do
  @moduledoc """
  Behaviour for browser automation adapters.

  Adapters implement the low-level browser control protocol, allowing
  JidoBrowser to work with different browser automation backends.

  ## Implementing an Adapter

      defmodule MyAdapter do
        @behaviour JidoBrowser.Adapter

        @impl true
        def start_session(opts) do
          # Start browser, return {:ok, session} or {:error, reason}
        end

        @impl true
        def end_session(session) do
          # Clean up resources
        end

        # ... implement other callbacks
      end

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
  """
  @callback navigate(session :: Session.t(), url :: String.t(), opts :: keyword()) ::
              {:ok, map()} | {:error, term()}

  @doc """
  Clicks an element matching the selector.
  """
  @callback click(session :: Session.t(), selector :: String.t(), opts :: keyword()) ::
              {:ok, map()} | {:error, term()}

  @doc """
  Types text into an element matching the selector.
  """
  @callback type(
              session :: Session.t(),
              selector :: String.t(),
              text :: String.t(),
              opts :: keyword()
            ) ::
              {:ok, map()} | {:error, term()}

  @doc """
  Takes a screenshot of the current page.
  """
  @callback screenshot(session :: Session.t(), opts :: keyword()) ::
              {:ok, %{bytes: binary(), mime: String.t()}} | {:error, term()}

  @doc """
  Extracts content from the current page.
  """
  @callback extract_content(session :: Session.t(), opts :: keyword()) ::
              {:ok, %{content: String.t(), format: atom()}} | {:error, term()}

  @doc """
  Executes JavaScript in the browser context.
  """
  @callback evaluate(session :: Session.t(), script :: String.t(), opts :: keyword()) ::
              {:ok, %{result: term()}} | {:error, term()}

  @optional_callbacks [evaluate: 3]
end
