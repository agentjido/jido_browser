defmodule Jido.Browser.FetchRichTest do
  use ExUnit.Case, async: false
  use Mimic

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
               browsey: [client: TestBrowseyClient, test_pid: self()]
             )

    assert_receive {:browsey_get, "https://example.com/browsey", _opts}
    assert result.retrieval_path == :browsey
    assert result.content =~ "Browsey body"
  end

  test "falls back to a browser session on blocked HTTP status when enabled" do
    session = test_session()

    expect(Req, :run, fn opts ->
      request = Req.Request.new(url: opts[:url])
      response = %Req.Response{status: 403, headers: %{"content-type" => ["text/html"]}, body: "Denied"}
      {request, response}
    end)

    expect(Jido.Browser, :start_session, fn opts ->
      assert opts[:pool] == :warm
      {:ok, session}
    end)

    expect(Jido.Browser, :navigate, fn ^session, "https://example.com/protected", opts ->
      assert opts[:timeout] == 30_000
      {:ok, session, %{url: "https://example.com/protected"}}
    end)

    expect(Jido.Browser, :snapshot, fn ^session, _opts ->
      {:ok, session, %{url: "https://example.com/protected", title: "Protected", snapshot: "Rendered body"}}
    end)

    expect(Jido.Browser, :end_session, fn ^session -> :ok end)

    assert {:ok, result} = Jido.Browser.fetch_rich("https://example.com/protected", pool: :warm)
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

    expect(Jido.Browser, :start_session, fn opts ->
      assert opts[:browser_fallback] == nil
      {:ok, session}
    end)

    expect(Jido.Browser, :navigate, fn ^session, "https://example.com/js", _opts ->
      {:ok, session, %{url: "https://example.com/js"}}
    end)

    expect(Jido.Browser, :snapshot, fn ^session, _opts ->
      {:ok, session, %{url: "https://example.com/js", title: "JS Page", snapshot: "Rendered JS content"}}
    end)

    expect(Jido.Browser, :end_session, fn ^session -> :ok end)

    assert {:ok, result} = Jido.Browser.fetch_rich("https://example.com/js", browser_fallback: true)
    assert result.retrieval_path == :browser
    assert result.fallback_reason == :blocked_content
    assert result.content == "Rendered JS content"
  end

  defp test_session do
    Session.new!(%{
      adapter: Jido.Browser.Adapters.AgentBrowser,
      connection: %{current_url: nil}
    })
  end
end
