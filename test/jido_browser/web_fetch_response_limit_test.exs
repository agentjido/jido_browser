defmodule Jido.Browser.WebFetchResponseLimitTest do
  use ExUnit.Case, async: false

  alias Jido.Browser.Error
  alias Jido.Browser.TestSupport.WebFetchServer
  alias Jido.Browser.WebFetch

  @backends [:req]

  setup do
    WebFetch.clear_cache()
    :ok
  end

  test "accepts exact bodies and rejects one extra byte for each transport framing" do
    for backend <- @backends,
        {framing, label} <- [{:content_length, "content-length"}, {:close, "connection-close"}, {:chunked, "chunked"}] do
      exact = start_server(fn _request -> response("1234", framing) end)

      assert {:ok, result} = fetch(backend, exact, "/#{label}", max_response_bytes: 4)
      assert result.content == "1234"

      over = start_server(fn _request -> response("12345", framing) end)

      assert_response_too_large(
        fetch(backend, over, "/#{label}-over", max_response_bytes: 4),
        backend,
        4
      )
    end
  end

  test "uses a high declared content length only for early rejection" do
    for backend <- @backends do
      server =
        start_server(fn _request ->
          %{status: 200, body: "small", declared_content_length: 100}
        end)

      details =
        assert_response_too_large(
          fetch(backend, server, "/false-high", max_response_bytes: 10),
          backend,
          10
        )

      assert details.declared_response_bytes == 100
      assert details.observed_response_bytes == 0
    end
  end

  test "treats a false low HTTP/1 content length as the protocol message boundary" do
    for backend <- @backends do
      server =
        start_server(fn _request ->
          %{status: 200, body: "123456", declared_content_length: 3}
        end)

      assert {:ok, result} = fetch(backend, server, "/false-low", max_response_bytes: 4)
      assert result.content == "123"
    end
  end

  test "infinity disables the Jido response limit without a sentinel integer" do
    body = String.duplicate("i", 96 * 1024)

    for backend <- @backends do
      server = start_server(fn _request -> response(body, :chunked) end)

      assert {:ok, result} = fetch(backend, server, "/infinity", max_response_bytes: :infinity)
      assert result.content == body
    end
  end

  test "rejects zero, negative, and invalid public limits" do
    for value <- [0, -1, "1024", nil] do
      assert {:error, %Error.InvalidError{} = error} =
               Jido.Browser.web_fetch("https://example.com/limit", max_response_bytes: value)

      assert error.details.error_code == :invalid_input
      assert error.details.option == :max_response_bytes
      assert error.details.value == value
    end
  end

  test "stops a large response before the fixture sends the complete body" do
    chunk = String.duplicate("s", 8 * 1024)
    total_chunks = 100

    for backend <- @backends do
      chunks = Stream.repeatedly(fn -> chunk end) |> Stream.take(total_chunks)

      server =
        start_server(fn _request ->
          %{
            status: 200,
            chunks: chunks,
            framing: :chunked,
            chunk_delay_ms: 5
          }
        end)

      assert_response_too_large(
        fetch(backend, server, "/abort", max_response_bytes: 32 * 1024),
        backend,
        32 * 1024
      )

      delivered = collect_server_chunks(server.pid, 500)

      assert Enum.count(delivered, fn {_index, result} -> result == :ok end) < total_chunks
      assert Enum.any?(delivered, fn {_index, result} -> match?({:error, _reason}, result) end)
    end
  end

  test "limits a redirect response before it follows the location" do
    for backend <- @backends do
      server =
        start_server(fn
          %{path: "/start"} ->
            %{status: 302, headers: [{"location", "/final"}], body: "12345"}

          %{path: "/final"} ->
            response("final", :content_length)
        end)

      assert_response_too_large(
        fetch(backend, server, "/start", max_response_bytes: 4),
        backend,
        4
      )

      server_pid = server.pid
      assert_receive {:web_fetch_server_request, ^server_pid, %{path: "/start"}}
      refute_receive {:web_fetch_server_request, ^server_pid, %{path: "/final"}}, 100
    end
  end

  test "applies the limit to the final response after a redirect" do
    for backend <- @backends do
      server =
        start_server(fn
          %{path: "/start"} ->
            %{status: 302, headers: [{"location", "/final"}], body: ""}

          %{path: "/final"} ->
            response("12345", :content_length)
        end)

      assert_response_too_large(
        fetch(backend, server, "/start", max_response_bytes: 4),
        backend,
        4
      )

      server_pid = server.pid
      assert_receive {:web_fetch_server_request, ^server_pid, %{path: "/start"}}
      assert_receive {:web_fetch_server_request, ^server_pid, %{path: "/final"}}
    end
  end

  test "keeps successful compressed responses decoded at the exact limit" do
    decoded = String.duplicate("d", 32 * 1024)
    encoded = :zlib.gzip(decoded)

    for backend <- @backends do
      server = start_server(fn _request -> gzip_response(encoded) end)

      assert {:ok, result} =
               fetch(backend, server, "/gzip-exact",
                 max_response_bytes: byte_size(decoded),
                 req: [compressed: true, retry: false]
               )

      assert result.content == decoded
      refute result.content == encoded
    end
  end

  test "stops compressed expansion soon after decoded output exceeds the limit" do
    decoded = String.duplicate("z", 2 * 1024 * 1024)
    encoded = :zlib.gzip(decoded)
    limit = 32 * 1024

    assert byte_size(encoded) < limit

    for backend <- @backends do
      server = start_server(fn _request -> gzip_response(encoded) end)

      details =
        assert_response_too_large(
          fetch(backend, server, "/gzip-over",
            max_response_bytes: limit,
            req: [compressed: true, retry: false]
          ),
          backend,
          limit
        )

      assert details.response_byte_semantics == :content_decoded
      assert details.observed_response_bytes > limit
      assert details.observed_response_bytes < byte_size(decoded)
      refute Map.has_key?(details, :body)
    end
  end

  if Req.Utils.zstd_available?() do
    test "keeps locked zstd decoding bounded when the runtime supports it" do
      exact = String.duplicate("e", 64 * 1024)
      exact_encoded = exact |> :zstd.compress() |> IO.iodata_to_binary()
      exact_server = start_server(fn _request -> encoded_response(exact_encoded, "zstd") end)

      assert {:ok, result} =
               fetch(:req, exact_server, "/zstd-exact",
                 max_response_bytes: byte_size(exact),
                 req: [compressed: true, retry: false]
               )

      assert result.content == exact

      expanded = String.duplicate("o", 2 * 1024 * 1024)
      expanded_encoded = expanded |> :zstd.compress() |> IO.iodata_to_binary()
      over_server = start_server(fn _request -> encoded_response(expanded_encoded, "zstd") end)

      details =
        assert_response_too_large(
          fetch(:req, over_server, "/zstd-over",
            max_response_bytes: 32 * 1024,
            req: [compressed: true, retry: false]
          ),
          :req,
          32 * 1024
        )

      assert details.response_byte_semantics == :content_decoded
      assert details.observed_response_bytes < byte_size(expanded)
    end
  end

  test "keeps max_content_tokens as a later post-processing limit" do
    body = String.duplicate("abcd", 10)
    server = start_server(fn _request -> response(body, :content_length) end)

    assert {:ok, result} =
             fetch(:req, server, "/tokens",
               max_response_bytes: 100,
               max_content_tokens: 2
             )

    assert result.truncated == true
    assert result.original_estimated_tokens == 10
    assert result.estimated_tokens <= 2
    assert byte_size(result.content) <= 8
  end

  defp response(body, framing) do
    %{status: 200, body: body, framing: framing}
  end

  defp gzip_response(encoded) do
    encoded_response(encoded, "gzip")
  end

  defp encoded_response(encoded, encoding) do
    %{
      status: 200,
      body: encoded,
      headers: [{"content-encoding", encoding}, {"content-type", "text/plain"}]
    }
  end

  defp start_server(responder) do
    server = WebFetchServer.start_http(self(), responder)
    on_exit(fn -> WebFetchServer.stop(server) end)
    server
  end

  defp fetch(backend, server, path, opts) do
    backend_opts =
      [
        allow_private_network: true,
        backend: backend,
        cache: false,
        format: :text,
        req: [retry: false]
      ]
      |> Keyword.merge(opts)

    Jido.Browser.web_fetch("http://127.0.0.1:#{server.port}#{path}", backend_opts)
  end

  defp assert_response_too_large(result, backend, limit) do
    assert {:error, %Error.AdapterError{} = error} = result

    assert error.message == "Web fetch response exceeds max_response_bytes"
    assert error.details.error_code == :response_too_large
    assert error.details.max_response_bytes == limit
    assert error.details.adapter == backend_module(backend)
    assert is_integer(error.details.observed_response_bytes)

    assert Map.keys(error.details) |> Enum.sort() ==
             [
               :adapter,
               :declared_response_bytes,
               :error_code,
               :max_response_bytes,
               :observed_response_bytes,
               :response_byte_semantics
             ]

    refute Map.has_key?(error.details, :reason)

    error.details
  end

  defp backend_module(:req), do: Jido.Browser.WebFetch.Backends.Req

  defp collect_server_chunks(server_pid, timeout) do
    deadline = System.monotonic_time(:millisecond) + timeout
    collect_server_chunks(server_pid, deadline, [])
  end

  defp collect_server_chunks(server_pid, deadline, chunks) do
    timeout = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {:web_fetch_server_chunk, ^server_pid, index, _size, result} ->
        collect_server_chunks(server_pid, deadline, [{index, result} | chunks])
    after
      timeout -> Enum.reverse(chunks)
    end
  end
end
