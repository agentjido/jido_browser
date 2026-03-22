defmodule Jido.Browser.WebFetchTest do
  use ExUnit.Case, async: false
  use Mimic

  alias Jido.Browser.Error
  alias Jido.Browser.WebFetch

  setup :set_mimic_global

  setup_all do
    Mimic.copy(Req)
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

    test "rejects URLs outside allowed_domains" do
      assert {:error, %Error.InvalidError{details: %{error_code: :url_not_allowed}}} =
               Jido.Browser.web_fetch(
                 "https://example.com/private",
                 allowed_domains: ["docs.example.com"]
               )
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
  end
end
