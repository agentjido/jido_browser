defmodule Jido.Browser.FetchRichTest do
  use ExUnit.Case, async: false
  use Mimic

  alias Jido.Browser.Adapters.AgentBrowser
  alias Jido.Browser.Error
  alias Jido.Browser.FetchRich
  alias Jido.Browser.Session
  alias Jido.Browser.WebFetch

  defmodule TestBrowseyClient do
    def get(url, opts) do
      send(opts[:test_pid], {:browsey_get, url, opts})

      {:ok,
       %{
         status: 200,
         headers: %{"content-type" => ["text/html"]},
         body: "<html><head><title>Browsey</title></head><body><main>Browsey body</main></body></html>",
         final_url: url
       }}
    end
  end

  setup :set_mimic_global

  setup_all do
    Mimic.copy(Req)
    Mimic.copy(AgentBrowser)
    Mimic.copy(WebFetch)
    :ok
  end

  setup do
    WebFetch.clear_cache()
    :ok
  end

  test "returns normalized HTTP result" do
    expect(Req, :run, fn opts ->
      request = Req.Request.new(url: opts[:url])

      response = %Req.Response{
        status: 200,
        headers: %{"content-type" => ["text/html"]},
        body: "<html><head><title>Article</title></head><body><main>Hello world.</main></body></html>"
      }

      {request, response}
    end)

    assert {:ok, result} = Jido.Browser.fetch_rich("https://example.com/article", selector: "main")
    assert result.retrieval_path == :web_fetch
    assert result.blocked? == false
    assert result.title == "Article"
    assert result.content =~ "Hello world."
  end

  test "supports Browsey as the selected HTTP path" do
    assert {:ok, result} =
             Jido.Browser.fetch_rich(
               "https://example.com/browsey",
               backend: :browsey,
               max_response_bytes: 2_048,
               browsey: [client: TestBrowseyClient, test_pid: self()]
             )

    assert_receive {:browsey_get, "https://example.com/browsey", opts}
    assert opts[:max_response_size_bytes] == 2_048
    assert result.retrieval_path == :browsey
    assert result.content =~ "Browsey body"
  end

  test "falls back to a browser session on blocked HTTP status when a pool option is present" do
    session = test_session()

    expect(Req, :run, fn opts ->
      request = Req.Request.new(url: opts[:url])
      response = %Req.Response{status: 403, headers: %{"content-type" => ["text/html"]}, body: "Denied"}
      {request, response}
    end)

    expect(AgentBrowser, :start_session, fn opts ->
      assert Keyword.has_key?(opts, :pool)
      assert opts[:pool] == nil
      {:ok, session}
    end)

    expect(AgentBrowser, :navigate, fn ^session, "https://example.com/protected", opts ->
      assert opts[:timeout] == 30_000
      {:ok, session, %{url: "https://example.com/protected"}}
    end)

    expect(AgentBrowser, :command, fn ^session, :snapshot, _opts ->
      {:ok, session, %{url: "https://example.com/protected", title: "Protected", snapshot: "Rendered body"}}
    end)

    expect(AgentBrowser, :end_session, fn ^session -> :ok end)

    assert {:ok, result} =
             Jido.Browser.fetch_rich("https://example.com/protected",
               adapter: AgentBrowser,
               pool: nil
             )

    assert result.retrieval_path == :browser
    assert result.fallback_reason == {:http_status, 403}
    assert result.content == "Rendered body"
    assert result.blocked? == false
  end

  test "falls back to a browser session for blocked challenge content when enabled" do
    session = test_session()

    expect(Req, :run, fn opts ->
      request = Req.Request.new(url: opts[:url])

      response = %Req.Response{
        status: 200,
        headers: %{"content-type" => ["text/html"]},
        body: "<html><body>Please enable JavaScript to continue.</body></html>"
      }

      {request, response}
    end)

    expect(AgentBrowser, :start_session, fn opts ->
      assert opts[:browser_fallback] == nil
      {:ok, session}
    end)

    expect(AgentBrowser, :navigate, fn ^session, "https://example.com/js", _opts ->
      {:ok, session, %{url: "https://example.com/js"}}
    end)

    expect(AgentBrowser, :command, fn ^session, :snapshot, _opts ->
      {:ok, session, %{url: "https://example.com/js", title: "JS Page", snapshot: "Rendered JS content"}}
    end)

    expect(AgentBrowser, :end_session, fn ^session -> :ok end)

    assert {:ok, result} = Jido.Browser.fetch_rich("https://example.com/js", browser_fallback: true)
    assert result.retrieval_path == :browser
    assert result.fallback_reason == :blocked_content
    assert result.content == "Rendered JS content"
  end

  test "forwards only HTTP options and returns successful HTTP metadata without starting a browser" do
    result = http_result("HTTP body")

    expect(WebFetch, :fetch, fn "https://example.com/http", opts ->
      assert opts ==
               [
                 backend: :browsey,
                 citations: true,
                 format: :text,
                 max_response_bytes: 4_096,
                 selector: "main",
                 timeout: 1_234
               ]

      {:ok, result}
    end)

    reject(AgentBrowser, :start_session, 1)

    assert {:ok, tagged_result} =
             FetchRich.fetch(
               "https://example.com/http",
               adapter: AgentBrowser,
               backend: :browsey,
               browser_fallback: true,
               citations: true,
               format: :text,
               max_response_bytes: 4_096,
               selector: "main",
               timeout: 1_234
             )

    assert tagged_result ==
             result
             |> Map.put(:retrieval_path, :browsey)
             |> Map.put(:fallback_reason, nil)
             |> Map.put(:blocked?, false)
  end

  test "does not start a browser for HTTP errors outside the fallback contract" do
    error = Error.adapter_error("HTTP request failed", %{status: 500, response: "failure"})

    expect(WebFetch, :fetch, fn "https://example.com/failure", [timeout: 30_000] ->
      {:error, error}
    end)

    reject(AgentBrowser, :start_session, 1)

    assert FetchRich.fetch(
             "https://example.com/failure",
             browser_fallback: true,
             timeout: 30_000
           ) == {:error, error}
  end

  test "does not start a browser when browser_fallback is truthy but not true" do
    error = Error.adapter_error("HTTP request failed", %{status: 403})

    expect(WebFetch, :fetch, fn "https://example.com/protected", [timeout: 30_000] ->
      {:error, error}
    end)

    reject(AgentBrowser, :start_session, 1)

    assert FetchRich.fetch(
             "https://example.com/protected",
             browser_fallback: :enabled,
             timeout: 30_000
           ) == {:error, error}
  end

  test "tries HTTP backends in order before browser fallback" do
    first_error = Error.adapter_error("HTTP request failed", %{status: 403})
    result = http_result("Second HTTP backend")
    test_pid = self()

    expect(WebFetch, :fetch, 2, fn "https://example.com/http-chain", opts ->
      send(test_pid, {:http_backend, opts[:backend]})

      case opts[:backend] do
        :first -> {:error, first_error}
        :second -> {:ok, result}
      end
    end)

    reject(AgentBrowser, :start_session, 1)

    assert {:ok, tagged_result} =
             FetchRich.fetch(
               "https://example.com/http-chain",
               browser_fallback: true,
               http_backends: [:first, :second],
               timeout: 700
             )

    assert_receive {:http_backend, :first}
    assert_receive {:http_backend, :second}
    assert tagged_result.retrieval_path == :web_fetch
    assert tagged_result.content == "Second HTTP backend"
  end

  test "preserves direct FetchRich timeout defaults across HTTP and browser calls" do
    session = test_session()
    http_error = Error.adapter_error("HTTP request failed", %{status: 403})

    expect(WebFetch, :fetch, fn "https://example.com/default-timeout", opts ->
      assert opts == [timeout: 30_000]
      {:error, http_error}
    end)

    expect(AgentBrowser, :start_session, fn opts ->
      assert opts == [adapter: AgentBrowser]
      {:ok, session}
    end)

    expect(AgentBrowser, :navigate, fn ^session, "https://example.com/default-timeout", opts ->
      assert opts == [timeout: nil]
      {:ok, session, %{url: "https://example.com/default-timeout"}}
    end)

    expect(AgentBrowser, :command, fn ^session, :snapshot, opts ->
      assert opts[:selector] == "body"
      assert opts[:max_content_length] == 50_000
      assert opts[:timeout] == 30_000
      {:ok, session, %{snapshot: "Rendered with defaults"}}
    end)

    expect(AgentBrowser, :end_session, fn ^session -> :ok end)

    assert {:ok, result} =
             FetchRich.fetch(
               "https://example.com/default-timeout",
               adapter: AgentBrowser,
               browser_fallback: true
             )

    assert result.content == "Rendered with defaults"
  end

  test "preserves the direct FetchRich error for unsupported HTTP formats" do
    reject(WebFetch, :fetch, 2)
    reject(AgentBrowser, :start_session, 1)

    assert {:error, %Error.InvalidError{} = error} =
             FetchRich.fetch("https://example.com/document", format: :pdf)

    assert error.message == "Unsupported web fetch format: :pdf"
    assert error.details == %{format: :pdf, supported: [:markdown, :html, :text]}
  end

  test "preserves empty URL validation for direct FetchRich and public Browser option forms" do
    expected_error = Error.invalid_error("URL cannot be nil or empty", %{url: ""})
    direct_fetch = &FetchRich.fetch/2

    for opts <- [[], [format: :html], [format: :pdf]] do
      assert direct_fetch.("", opts) == {:error, expected_error}
      assert Jido.Browser.fetch_rich("", opts) == {:error, expected_error}
    end

    assert_raise FunctionClauseError, ~r/Jido\.Browser\.FetchRich\.fetch\/2/, fn ->
      invoke(direct_fetch, "", %{})
    end

    assert Jido.Browser.fetch_rich("", %{}) == {:error, expected_error}
  end

  test "preserves adjacent whitespace and invalid URI validation" do
    whitespace_error = Error.invalid_error("URL cannot be empty", %{error_code: :invalid_input})

    invalid_uri_error =
      Error.invalid_error("Web fetch only supports http and https URLs", %{
        error_code: :invalid_input,
        scheme: nil
      })

    for entrypoint <- [&FetchRich.fetch/2, &Jido.Browser.fetch_rich/2] do
      assert entrypoint.("   ", []) == {:error, whitespace_error}
      assert entrypoint.("not a url", []) == {:error, invalid_uri_error}
    end
  end

  test "preserves adjacent non-binary and non-list option behavior" do
    direct_fetch = &FetchRich.fetch/2
    browser_fetch = &Jido.Browser.fetch_rich/2

    for url <- [nil, 123] do
      assert_raise FunctionClauseError, ~r/Jido\.Browser\.FetchRich\.fetch\/2/, fn ->
        direct_fetch.(url, [])
      end
    end

    nil_error = Error.invalid_error("URL cannot be nil or empty", %{url: nil})
    assert Jido.Browser.fetch_rich(nil, []) == {:error, nil_error}

    browser_function_clause = ~r/Jido\.Browser(?:\.Mimic\.Original\.Module)?\.fetch_rich\/2/

    assert_raise FunctionClauseError, browser_function_clause, fn ->
      invoke(browser_fetch, 123, [])
    end

    assert_raise FunctionClauseError, ~r/Jido\.Browser\.FetchRich\.fetch\/2/, fn ->
      invoke(direct_fetch, "https://example.com", %{})
    end

    assert_raise FunctionClauseError, ~r/Keyword\.put_new\/3/, fn ->
      invoke(browser_fetch, "https://example.com", %{})
    end
  end

  test "uses the browser after a fallback HTTP error and preserves options, metadata, and cleanup order" do
    session = test_session()
    http_error = Error.adapter_error("HTTP request failed", %{status: 403})
    test_pid = self()

    expect(WebFetch, :fetch, fn "https://example.com/protected", opts ->
      send(test_pid, {:trace, :http})
      assert opts == [citations: true, format: :markdown, max_content_tokens: 3, selector: "article", timeout: 9_876]
      {:error, http_error}
    end)

    expect(AgentBrowser, :start_session, fn opts ->
      send(test_pid, {:trace, :start_session})

      assert opts ==
               [
                 adapter: AgentBrowser,
                 checkout_timeout: 2_000,
                 headless: false,
                 timeout: 9_876
               ]

      {:ok, session}
    end)

    expect(AgentBrowser, :navigate, fn ^session, "https://example.com/protected", opts ->
      send(test_pid, {:trace, :navigate})
      assert opts == [timeout: 9_876]
      {:ok, session, %{url: "https://example.com/rendered"}}
    end)

    expect(AgentBrowser, :command, fn ^session, :snapshot, opts ->
      send(test_pid, {:trace, :snapshot})
      assert opts == [max_content_length: 12, selector: "article", timeout: 9_876]

      {:ok, session,
       %{
         url: "https://example.com/rendered",
         title: "Rendered title",
         snapshot: "Rendered body that is longer than twelve characters"
       }}
    end)

    expect(AgentBrowser, :end_session, fn ^session ->
      send(test_pid, {:trace, :end_session})
      :ok
    end)

    assert {:ok, result} =
             FetchRich.fetch(
               "https://example.com/protected",
               adapter: AgentBrowser,
               browser_fallback: true,
               checkout_timeout: 2_000,
               citations: true,
               format: :markdown,
               headless: false,
               max_content_tokens: 3,
               selector: "article",
               timeout: 9_876
             )

    assert_receive {:trace, :http}
    assert_receive {:trace, :start_session}
    assert_receive {:trace, :navigate}
    assert_receive {:trace, :snapshot}
    assert_receive {:trace, :end_session}

    assert result == %{
             blocked?: false,
             cached: false,
             citations: %{enabled: true},
             content: "Rendered bod",
             content_type: "text/html",
             document_type: :html,
             estimated_tokens: 3,
             fallback_reason: {:http_status, 403},
             filtered: false,
             final_url: "https://example.com/rendered",
             focus_matches: 0,
             format: :markdown,
             original_estimated_tokens: 13,
             passages: [
               %{
                 end_char: 12,
                 index: 0,
                 start_char: 0,
                 text: "Rendered bod",
                 title: "Rendered title",
                 url: "https://example.com/rendered"
               }
             ],
             retrieval_path: :browser,
             retrieved_at: result.retrieved_at,
             title: "Rendered title",
             truncated: true,
             url: "https://example.com/rendered"
           }
  end

  test "uses extraction after a snapshot error and always ends the browser session" do
    session = test_session()
    http_error = Error.adapter_error("HTTP request failed", %{error_code: :url_not_accessible})
    snapshot_error = Error.adapter_error("Snapshot failed", %{})

    expect(WebFetch, :fetch, fn "https://example.com/extract", [format: :text, selector: "main", timeout: 500] ->
      {:error, http_error}
    end)

    expect(AgentBrowser, :start_session, fn [adapter: AgentBrowser, timeout: 500] ->
      {:ok, session}
    end)

    expect(AgentBrowser, :navigate, fn ^session, "https://example.com/extract", [timeout: 500] ->
      {:ok, session, %{url: "https://example.com/final"}}
    end)

    expect(AgentBrowser, :command, fn ^session, :snapshot, opts ->
      assert opts == [max_content_length: 50_000, selector: "main", timeout: 500]
      {:error, snapshot_error}
    end)

    expect(AgentBrowser, :extract_content, fn ^session, opts ->
      assert opts == [format: :text, selector: "main", timeout: 500]
      {:ok, session, %{content: "Extracted text", format: :text, title: "Extracted title"}}
    end)

    expect(AgentBrowser, :end_session, fn ^session -> :ok end)

    assert {:ok, result} =
             FetchRich.fetch(
               "https://example.com/extract",
               adapter: AgentBrowser,
               browser_fallback: true,
               format: :text,
               selector: "main",
               timeout: 500
             )

    assert result.content == "Extracted text"
    assert result.final_url == "https://example.com/final"
    assert result.title == "Extracted title"
    assert result.format == :text
    assert result.fallback_reason == :url_not_accessible
  end

  test "wraps navigation errors and ends an already-started browser session" do
    session = test_session()
    http_error = Error.adapter_error("HTTP request failed", %{status: 429})
    navigation_error = Error.navigation_error("https://example.com/rate-limited", :timeout)

    expect(WebFetch, :fetch, fn "https://example.com/rate-limited", [timeout: 250] ->
      {:error, http_error}
    end)

    expect(AgentBrowser, :start_session, fn [adapter: AgentBrowser, timeout: 250] ->
      {:ok, session}
    end)

    expect(AgentBrowser, :navigate, fn ^session, "https://example.com/rate-limited", [timeout: 250] ->
      {:error, navigation_error}
    end)

    expect(AgentBrowser, :end_session, fn ^session -> :ok end)

    assert {:error, %Error.AdapterError{} = error} =
             FetchRich.fetch(
               "https://example.com/rate-limited",
               adapter: AgentBrowser,
               browser_fallback: true,
               timeout: 250
             )

    assert error.message == "Browser fallback failed"

    assert error.details == %{
             fallback_reason: {:http_status, 429},
             reason: navigation_error,
             url: "https://example.com/rate-limited"
           }
  end

  test "wraps browser start errors without attempting cleanup" do
    http_error = Error.adapter_error("HTTP request failed", %{status: 401})
    start_error = Error.adapter_error("Start failed", %{reason: :unavailable})

    expect(WebFetch, :fetch, fn "https://example.com/login", [timeout: 100] ->
      {:error, http_error}
    end)

    expect(AgentBrowser, :start_session, fn [adapter: AgentBrowser, timeout: 100] ->
      {:error, start_error}
    end)

    reject(AgentBrowser, :end_session, 1)

    assert {:error, %Error.AdapterError{} = error} =
             FetchRich.fetch(
               "https://example.com/login",
               adapter: AgentBrowser,
               browser_fallback: true,
               timeout: 100
             )

    assert error.message == "Browser fallback failed to start"

    assert error.details == %{
             fallback_reason: {:http_status, 401},
             reason: start_error,
             url: "https://example.com/login"
           }
  end

  test "returns blocked HTTP metadata when browser fallback is disabled" do
    result = http_result("Please verify you are human")

    expect(WebFetch, :fetch, fn "https://example.com/challenge", [timeout: 30_000] ->
      {:ok, result}
    end)

    reject(AgentBrowser, :start_session, 1)

    assert {:ok, tagged_result} = FetchRich.fetch("https://example.com/challenge", timeout: 30_000)

    assert tagged_result ==
             result
             |> Map.put(:retrieval_path, :web_fetch)
             |> Map.put(:fallback_reason, :blocked_content)
             |> Map.put(:blocked?, true)
  end

  defp http_result(content) do
    %{
      cached: false,
      citations: %{enabled: false},
      content: content,
      content_type: "text/html",
      document_type: :html,
      estimated_tokens: 3,
      filtered: false,
      final_url: "https://example.com/final",
      focus_matches: 0,
      format: :markdown,
      original_estimated_tokens: 3,
      passages: [],
      retrieved_at: "2026-08-27T12:00:00Z",
      title: "HTTP title",
      truncated: false,
      url: "https://example.com/final"
    }
  end

  defp invoke(function, first, second), do: function.(first, second)

  defp test_session do
    Session.new!(%{
      adapter: Jido.Browser.Adapters.AgentBrowser,
      connection: %{current_url: nil}
    })
  end
end
