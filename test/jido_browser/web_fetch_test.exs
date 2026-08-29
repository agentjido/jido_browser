defmodule Jido.Browser.WebFetchTest do
  use ExUnit.Case, async: false
  use Mimic

  alias Jido.Browser.Error
  alias Jido.Browser.WebFetch

  @result_keys ~w(
    cached citations content content_type document_type estimated_tokens filtered final_url
    focus_matches format original_estimated_tokens passages retrieved_at title truncated url
  )a

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
    test "rejects the removed Browsey backend alias" do
      assert {:error, %Error.InvalidError{details: %{backend: :browsey}}} =
               Jido.Browser.web_fetch("https://example.com", backend: :browsey, cache: false)
    end

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
      assert result |> Map.keys() |> Enum.sort() == Enum.sort(@result_keys)
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

    test "keeps the public facade and direct WebFetch result contract equivalent" do
      expect(Req, :run, 2, fn opts ->
        request = Req.Request.new(url: opts[:url])

        response =
          %Req.Response{
            status: 200,
            headers: %{"content-type" => ["text/plain"]},
            body: "public API content"
          }

        {request, response}
      end)

      url = "https://example.com/public-api.txt"
      opts = [format: :text, cache: false]

      assert {:ok, facade_result} = Jido.Browser.web_fetch(url, opts)
      assert {:ok, direct_result} = WebFetch.fetch(url, opts)

      assert Map.drop(facade_result, [:retrieved_at]) == Map.drop(direct_result, [:retrieved_at])
      assert facade_result |> Map.keys() |> Enum.sort() == Enum.sort(@result_keys)
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

    test "expires zero-TTL entries without returning a cache hit" do
      expect(Req, :run, 2, fn opts ->
        request = Req.Request.new(url: opts[:url])

        response =
          %Req.Response{
            status: 200,
            headers: %{"content-type" => ["text/plain"]},
            body: "zero TTL content"
          }

        {request, response}
      end)

      options = [format: :text, cache_ttl_ms: 0]

      assert {:ok, first} = Jido.Browser.web_fetch("https://example.com/zero-ttl.txt", options)
      assert {:ok, second} = Jido.Browser.web_fetch("https://example.com/zero-ttl.txt", options)

      refute first.cached
      refute second.cached
    end

    test "canonicalizes backend options and keeps response limits in the cache key" do
      expect(Req, :run, 2, fn opts ->
        request = Req.Request.new(url: opts[:url])

        response =
          %Req.Response{
            status: 200,
            headers: %{"content-type" => ["text/plain"]},
            body: "cache key content"
          }

        {request, response}
      end)

      url = "https://example.com/cache-key.txt"

      assert {:ok, first} =
               Jido.Browser.web_fetch(url,
                 format: :text,
                 req: [pool_timeout: 100, connect_options: [timeout: 200, protocols: [:http1]]]
               )

      assert {:ok, reordered} =
               Jido.Browser.web_fetch(url,
                 format: :text,
                 req: [connect_options: [protocols: [:http1], timeout: 200], pool_timeout: 100]
               )

      assert {:ok, different_limit} =
               Jido.Browser.web_fetch(url,
                 format: :text,
                 max_response_bytes: 1_024,
                 req: [connect_options: [timeout: 200, protocols: [:http1]], pool_timeout: 100]
               )

      refute first.cached
      assert reordered.cached
      refute different_limit.cached
    end

    test "does not cache a response-limit failure or its partial body" do
      counter_key = {__MODULE__, make_ref()}

      expect(Req, :run, 2, fn opts ->
        request = Req.Request.new(url: opts[:url])
        count = Process.get(counter_key, 0)
        Process.put(counter_key, count + 1)

        response =
          if count == 0 do
            %Req.Response{
              status: 200,
              headers: %{"content-type" => ["text/plain"]},
              body:
                {:jido_browser_response_too_large,
                 %{
                   max_response_bytes: 10,
                   observed_response_bytes: 11,
                   response_byte_semantics: :transfer_body
                 }}
            }
          else
            %Req.Response{
              status: 200,
              headers: %{"content-type" => ["text/plain"]},
              body: "complete response"
            }
          end

        {request, response}
      end)

      url = "https://example.com/partial-response.txt"

      assert {:error, %Error.AdapterError{details: %{error_code: :response_too_large}}} =
               Jido.Browser.web_fetch(url, format: :text)

      assert {:ok, complete} = Jido.Browser.web_fetch(url, format: :text)
      assert {:ok, cached} = Jido.Browser.web_fetch(url, format: :text)

      refute complete.cached
      assert cached.cached
      assert cached.content == "complete response"
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
                 allow_private_network: true,
                 test_pid: self()
               )

      assert_receive {:test_backend_fetch, "https://example.com/backend-cache.txt", opts}
      assert opts[:test_pid] == self()
      assert opts[:max_response_bytes] == 5 * 1024 * 1024
      assert first.content == "req backend content"
      assert second.content == "custom backend content"
    end

    test "uses the configured backend when no runtime backend is provided" do
      previous = Application.get_env(:jido_browser, :web_fetch, :__unset__)

      Application.put_env(
        :jido_browser,
        :web_fetch,
        backend: TestBackend,
        max_response_bytes: 12_345,
        resolver: Jido.Browser.TestSupport.WebFetchResolver
      )

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
                 allow_private_network: true,
                 test_pid: self()
               )

      assert_receive {:test_backend_fetch, "https://example.com/configured-backend.txt", opts}
      assert opts[:test_pid] == self()
      assert opts[:max_response_bytes] == 12_345
      assert result.content == "custom backend content"
    end
  end
end
