defmodule Jido.Browser.WebFetchTest do
  use ExUnit.Case, async: false
  use Mimic

  alias Jido.Browser.Error
  alias Jido.Browser.WebFetch

  defmodule TestBackend do
    @behaviour Jido.Browser.WebFetch.Backend

    @impl true
    def fetch(url, opts) do
      send(opts[:test_pid], {:test_backend_fetch, url, opts})

      {:ok,
       %{
         status: 200,
         headers: %{"content-type" => ["text/plain"]},
         body: "custom backend content",
         final_url: url
       }}
    end
  end

  defmodule TestBrowseyClient do
    def get(url, opts) do
      send(opts[:test_pid], {:browsey_get, url, opts})

      {:ok,
       %{
         status: 200,
         headers: %{"content-type" => ["text/html; charset=utf-8"]},
         body: """
         <html>
           <head><title>Browsey Page</title></head>
           <body><main><h1>Stealth HTTP</h1><p>Fetched by Browsey.</p></main></body>
         </html>
         """,
         final_uri: URI.parse("https://example.com/final"),
         uri_sequence: [URI.parse("https://example.com/stealth"), URI.parse("https://example.com/final")],
         runtime_ms: 12
       }}
    end
  end

  setup :set_mimic_global

  setup_all do
    Mimic.copy(Req)
    Mimic.copy(ExtractousEx)
    :ok
  end

  setup do
    WebFetch.clear_cache()
    :ok
  end

  describe "web_fetch/2" do
    test "fetches HTML content with selector extraction and citation passages" do
      expect(Req, :run, fn opts ->
        assert opts[:url] == "https://example.com/article"
        assert opts[:decode_body] == false

        request = Req.Request.new(url: "https://example.com/article")

        response =
          %Req.Response{
            status: 200,
            headers: %{"content-type" => ["text/html; charset=utf-8"]},
            body: """
            <html>
              <head><title>Example Article</title></head>
              <body>
                <nav>Ignore me</nav>
                <main>
                  <h1>Hello</h1>
                  <p>Alpha paragraph.</p>
                  <p>Beta paragraph.</p>
                </main>
              </body>
            </html>
            """
          }

        {request, response}
      end)

      assert {:ok, result} =
               Jido.Browser.web_fetch(
                 "https://example.com/article",
                 selector: "main",
                 format: :markdown,
                 citations: true
               )

      assert result.title == "Example Article"
      assert result.document_type == :html
      assert result.format == :markdown
      assert result.content =~ "Hello"
      assert result.content =~ "Alpha paragraph."
      assert result.cached == false
      assert result.citations.enabled == true
      assert [%{start_char: 0, text: passage_text} | _] = result.passages
      assert passage_text =~ "Hello"
    end

    test "preserves JSON responses as text content" do
      expect(Req, :run, fn opts ->
        assert opts[:decode_body] == false
        request = Req.Request.new(url: opts[:url])

        response =
          %Req.Response{
            status: 200,
            headers: %{"content-type" => ["application/json"]},
            body: ~s({"name":"jido","kind":"agent"})
          }

        {request, response}
      end)

      assert {:ok, result} = Jido.Browser.web_fetch("https://example.com/data.json", format: :text)

      assert result.document_type == :text
      assert result.content =~ ~s("name":"jido")
    end

    test "applies focused filtering to plain text responses" do
      expect(Req, :run, fn opts ->
        request = Req.Request.new(url: opts[:url])

        response =
          %Req.Response{
            status: 200,
            headers: %{"content-type" => ["text/plain"]},
            body: """
            Intro section

            The relevant paragraph mentions Elixir and OTP.

            Closing section
            """
          }

        {request, response}
      end)

      assert {:ok, result} =
               Jido.Browser.web_fetch(
                 "https://example.com/notes.txt",
                 format: :text,
                 focus_terms: ["elixir"]
               )

      assert result.filtered == true
      assert result.focus_matches == 1
      assert result.content =~ "relevant paragraph"
      refute result.content =~ "Intro section"
    end

    test "extracts PDF content through ExtractousEx and preserves metadata" do
      pdf_bytes = "%PDF-1.7 fake"

      expect(Req, :run, fn opts ->
        request = Req.Request.new(url: opts[:url])

        response =
          %Req.Response{
            status: 200,
            headers: %{"content-type" => ["application/pdf"]},
            body: pdf_bytes
          }

        {request, response}
      end)

      expect(ExtractousEx, :extract_from_bytes, fn ^pdf_bytes, opts ->
        assert opts == []

        {:ok,
         %{
           content: "Extracted PDF body",
           metadata: %{"title" => "Quarterly Report", "author" => "Ops"}
         }}
      end)

      assert {:ok, result} =
               Jido.Browser.web_fetch(
                 "https://example.com/reports/q1.pdf",
                 format: :text,
                 citations: true
               )

      assert result.title == "Quarterly Report"
      assert result.document_type == :pdf
      assert result.content_type == "application/pdf"
      assert result.content == "Extracted PDF body"
      assert result.metadata == %{"title" => "Quarterly Report", "author" => "Ops"}
      assert result.citations.enabled == true
      assert [%{text: "Extracted PDF body"}] = result.passages
    end

    test "extracts office documents served as octet-stream based on file extension" do
      docx_bytes = <<80, 75, 3, 4, 20, 0, 0, 0>>

      expect(Req, :run, fn opts ->
        request = Req.Request.new(url: opts[:url])

        response =
          %Req.Response{
            status: 200,
            headers: %{"content-type" => ["application/octet-stream"]},
            body: docx_bytes
          }

        {request, response}
      end)

      expect(ExtractousEx, :extract_from_bytes, fn ^docx_bytes, opts ->
        assert opts == []
        {:ok, %{content: "DOCX body", metadata: %{}}}
      end)

      assert {:ok, result} =
               Jido.Browser.web_fetch("https://example.com/specs/design.docx", format: :markdown)

      assert result.title == "design.docx"
      assert result.document_type == :word_processing
      assert result.content_type == "application/octet-stream"
      assert result.content == "DOCX body"
    end

    test "returns an adapter error when ExtractousEx extraction fails" do
      pdf_bytes = "%PDF-1.7 broken"

      expect(Req, :run, fn opts ->
        request = Req.Request.new(url: opts[:url])

        response =
          %Req.Response{
            status: 200,
            headers: %{"content-type" => ["application/pdf"]},
            body: pdf_bytes
          }

        {request, response}
      end)

      expect(ExtractousEx, :extract_from_bytes, fn ^pdf_bytes, [] ->
        {:error, "parse failed"}
      end)

      assert {:error, %Error.AdapterError{details: %{error_code: :unavailable, document_type: :pdf}}} =
               Jido.Browser.web_fetch("https://example.com/broken.pdf", format: :text)
    end

    test "rejects URLs outside allowed_domains" do
      assert {:error, %Error.InvalidError{details: %{error_code: :url_not_allowed}}} =
               Jido.Browser.web_fetch(
                 "https://example.com/private",
                 allowed_domains: ["docs.example.com"]
               )
    end

    test "rejects invalid direct API options early" do
      assert {:error, %Error.InvalidError{details: %{option: :timeout, error_code: :invalid_input}}} =
               Jido.Browser.web_fetch("https://example.com/notes.txt", timeout: 0)

      assert {:error, %Error.InvalidError{details: %{extractous: [:bad, :shape], error_code: :invalid_input}}} =
               Jido.Browser.web_fetch("https://example.com/notes.txt", extractous: [:bad, :shape])
    end

    test "enforces known URL provenance when requested" do
      assert {:error, %Error.InvalidError{details: %{error_code: :url_not_allowed}}} =
               Jido.Browser.web_fetch(
                 "https://example.com/private",
                 require_known_url: true,
                 known_urls: ["https://example.com/public"]
               )
    end

    test "caps returned content by approximate token budget" do
      expect(Req, :run, fn opts ->
        request = Req.Request.new(url: opts[:url])

        response =
          %Req.Response{
            status: 200,
            headers: %{"content-type" => ["text/plain"]},
            body: String.duplicate("abcdef", 20)
          }

        {request, response}
      end)

      assert {:ok, result} =
               Jido.Browser.web_fetch(
                 "https://example.com/large.txt",
                 format: :text,
                 max_content_tokens: 5
               )

      assert result.truncated == true
      assert result.original_estimated_tokens > 5
      assert result.estimated_tokens <= 5
    end

    test "reuses cached responses for identical requests" do
      expect(Req, :run, fn opts ->
        request = Req.Request.new(url: opts[:url])

        response =
          %Req.Response{
            status: 200,
            headers: %{"content-type" => ["text/plain"]},
            body: "cached content"
          }

        {request, response}
      end)

      assert {:ok, first} = Jido.Browser.web_fetch("https://example.com/cache.txt", format: :text)
      assert {:ok, second} = Jido.Browser.web_fetch("https://example.com/cache.txt", format: :text)

      assert first.cached == false
      assert second.cached == true
      assert first.content == second.content
    end

    test "separates cache entries by backend" do
      expect(Req, :run, fn opts ->
        request = Req.Request.new(url: opts[:url])

        response =
          %Req.Response{
            status: 200,
            headers: %{"content-type" => ["text/plain"]},
            body: "req backend content"
          }

        {request, response}
      end)

      assert {:ok, first} = Jido.Browser.web_fetch("https://example.com/backend-cache.txt", format: :text)

      assert {:ok, second} =
               Jido.Browser.web_fetch(
                 "https://example.com/backend-cache.txt",
                 format: :text,
                 backend: TestBackend,
                 test_pid: self()
               )

      assert_receive {:test_backend_fetch, "https://example.com/backend-cache.txt", opts}
      assert opts[:test_pid] == self()
      assert first.content == "req backend content"
      assert second.content == "custom backend content"
    end

    test "uses the configured backend when no runtime backend is provided" do
      previous = Application.get_env(:jido_browser, :web_fetch, :__unset__)

      Application.put_env(:jido_browser, :web_fetch, backend: TestBackend)

      on_exit(fn ->
        if previous == :__unset__ do
          Application.delete_env(:jido_browser, :web_fetch)
        else
          Application.put_env(:jido_browser, :web_fetch, previous)
        end
      end)

      assert {:ok, result} =
               Jido.Browser.web_fetch(
                 "https://example.com/configured-backend.txt",
                 format: :text,
                 cache: false,
                 test_pid: self()
               )

      assert_receive {:test_backend_fetch, "https://example.com/configured-backend.txt", opts}
      assert opts[:test_pid] == self()
      assert result.content == "custom backend content"
    end

    test "routes through Browsey backend and preserves normalized result shape" do
      assert {:ok, result} =
               Jido.Browser.web_fetch(
                 "https://example.com/stealth",
                 format: :markdown,
                 selector: "main",
                 backend: :browsey,
                 browsey: [
                   browser: :safari,
                   max_response_size_bytes: 1_000_000,
                   client: TestBrowseyClient,
                   test_pid: self()
                 ]
               )

      assert_receive {:browsey_get, "https://example.com/stealth", opts}
      assert opts[:browser] == :safari
      assert opts[:max_response_size_bytes] == 1_000_000
      assert opts[:timeout] == 30_000
      assert opts[:follow_redirects?] == true
      refute Keyword.has_key?(opts, :client)

      assert result.title == "Browsey Page"
      assert result.final_url == "https://example.com/final"
      assert result.document_type == :html
      assert result.format == :markdown
      assert result.content =~ "Stealth HTTP"
      assert result.content =~ "Fetched by Browsey."
      assert result.cached == false
      assert result.passages == []
    end

    @tag :integration
    @tag timeout: 60_000
    test "smoke tests real Browsey backend against example.com" do
      assert {:ok, result} =
               Jido.Browser.web_fetch(
                 "https://example.com",
                 backend: :browsey,
                 format: :markdown,
                 cache: false,
                 timeout: 30_000,
                 browsey: [
                   browser: :chrome,
                   max_response_size_bytes: 1_000_000
                 ]
               )

      assert result.title == "Example Domain"
      assert result.document_type == :html
      assert result.content =~ "Example Domain"
    end
  end
end
