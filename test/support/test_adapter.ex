defmodule JidoBrowser.Adapters.Test do
  @moduledoc """
  In-memory test adapter for JidoBrowser.

  Simulates browser behavior without requiring a real browser.
  Useful for unit testing actions and workflows.
  """

  @behaviour JidoBrowser.Adapter

  alias JidoBrowser.Session

  @impl true
  def start_session(opts \\ []) do
    Session.new(%{
      adapter: __MODULE__,
      connection: %{
        current_url: nil,
        title: "",
        html: "<html><body></body></html>",
        history: [],
        elements: %{}
      },
      opts: Map.new(opts)
    })
  end

  @impl true
  def end_session(_session), do: :ok

  @impl true
  def navigate(%Session{connection: connection} = session, url, _opts) do
    updated_connection = Map.put(connection, :current_url, url)
    updated_session = %{session | connection: updated_connection}
    {:ok, updated_session, %{url: url, title: "Test Page - #{url}"}}
  end

  @impl true
  def click(%Session{} = session, selector, _opts) do
    {:ok, session, %{selector: selector, clicked: true}}
  end

  @impl true
  def type(%Session{} = session, selector, text, _opts) do
    {:ok, session, %{selector: selector, typed: text}}
  end

  @impl true
  def screenshot(%Session{} = session, opts) do
    format = opts[:format] || :png
    _full_page = opts[:full_page] || false

    case format do
      :png ->
        png = <<137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82>>
        {:ok, session, %{bytes: png, mime: "image/png", format: :png}}

      :jpeg ->
        {:error,
         JidoBrowser.Error.adapter_error("Test adapter only supports PNG screenshots", %{
           requested_format: :jpeg,
           supported_formats: [:png]
         })}

      other ->
        {:error,
         JidoBrowser.Error.adapter_error("Unsupported screenshot format", %{
           requested_format: other,
           supported_formats: [:png]
         })}
    end
  end

  @impl true
  def extract_content(%Session{} = session, opts) do
    format = opts[:format] || :markdown

    content =
      case format do
        :html -> "<h1>Test Page</h1><p>This is test content.</p>"
        :text -> "Test Page\n\nThis is test content."
        _ -> "# Test Page\n\nThis is test content."
      end

    {:ok, session, %{content: content, format: format}}
  end

  @impl true
  def evaluate(%Session{} = session, script, _opts) do
    result = simulate_js(script)
    {:ok, session, %{result: result}}
  end

  # Simulate common JS expressions - intentionally a large pattern matcher for test mocking
  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  defp simulate_js(script) do
    cond do
      script =~ "document.title" ->
        "Test Page"

      script =~ "window.location.href" ->
        "https://test.local/page"

      script =~ "history.back" ->
        nil

      script =~ "history.forward" ->
        nil

      script =~ "location.reload" ->
        nil

      script =~ "scrollTo" or script =~ "scrollBy" ->
        nil

      script =~ "querySelector" ->
        %{"found" => true}

      script =~ "waitForSelector" ->
        %{"found" => true, "elapsed" => 100}

      script =~ "waitForNav" ->
        %{"url" => "https://test.local/new", "elapsed" => 50}

      script =~ "snapshot" ->
        %{
          "url" => "https://test.local",
          "title" => "Test Page",
          "content" => "Test content here",
          "links" => [%{"id" => "link_0", "text" => "Click me", "href" => "/page"}],
          "forms" => [],
          "headings" => [%{"level" => 1, "text" => "Main Heading"}],
          "meta" => %{"viewport_height" => 720, "scroll_height" => 1200, "scroll_position" => 0}
        }

      script =~ "querySelectorAll" ->
        [
          %{"index" => 0, "tag" => "div", "id" => "test", "classes" => ["foo"], "text" => "Hello"}
        ]

      script =~ "innerText" ->
        "Element text content"

      script =~ "getAttribute" ->
        "attribute-value"

      script =~ "offsetParent" ->
        %{"exists" => true, "visible" => true}

      script =~ "focus" ->
        %{"focused" => true}

      script =~ "dispatchEvent" ->
        true

      script =~ "selectedIndex" or script =~ "select.value" ->
        true

      true ->
        nil
    end
  end
end
