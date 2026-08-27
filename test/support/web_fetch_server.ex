defmodule Jido.Browser.TestSupport.WebFetchServer do
  @moduledoc false

  @type request :: %{
          required(:body) => binary(),
          required(:headers) => map(),
          required(:method) => String.t(),
          required(:path) => String.t()
        }
  @type response :: %{
          optional(:body) => binary(),
          optional(:chunks) => Enumerable.t(),
          optional(:declared_content_length) => non_neg_integer(),
          optional(:framing) => :content_length | :chunked | :close,
          optional(:headers) => [{String.t(), String.t()}],
          required(:status) => pos_integer()
        }

  @doc false
  @type response_action :: response() | :close | :reset

  @spec start_http(pid(), (request() -> response_action()), keyword()) :: map()
  def start_http(owner, responder, opts \\ []) when is_pid(owner) and is_function(responder, 1) do
    ip = Keyword.get(opts, :ip, {127, 0, 0, 1})
    port = Keyword.get(opts, :port, 0)

    listen_options = [:binary, active: false, ip: ip, reuseaddr: true] ++ address_family_options(ip)

    {:ok, listener} = :gen_tcp.listen(port, listen_options)

    {:ok, port} = :inet.port(listener)
    pid = spawn(fn -> accept_loop(:tcp, listener, owner, responder) end)
    %{ip: ip, listener: listener, pid: pid, port: port, scheme: "http"}
  end

  @doc false
  @spec start_https(pid(), (request() -> response())) :: map()
  def start_https(owner, responder) when is_pid(owner) and is_function(responder, 1) do
    {:ok, listener} =
      :ssl.listen(0,
        certfile: fixture_path("server.pem"),
        keyfile: fixture_path("server-key.pem"),
        mode: :binary,
        active: false,
        ip: {127, 0, 0, 1},
        reuseaddr: true
      )

    {:ok, {_address, port}} = :ssl.sockname(listener)
    pid = spawn(fn -> accept_loop(:ssl, listener, owner, responder) end)
    %{listener: listener, pid: pid, port: port, scheme: "https"}
  end

  @doc false
  @spec ca_certificate_path() :: charlist()
  def ca_certificate_path, do: fixture_path("ca.pem")

  @doc false
  @spec stop(map()) :: :ok
  def stop(%{listener: listener, pid: pid, scheme: "http"}) do
    :gen_tcp.close(listener)
    stop_process(pid)
  end

  def stop(%{listener: listener, pid: pid, scheme: "https"}) do
    :ssl.close(listener)
    stop_process(pid)
  end

  defp accept_loop(:tcp, listener, owner, responder) do
    case :gen_tcp.accept(listener) do
      {:ok, socket} ->
        serve(:tcp, socket, owner, responder)
        accept_loop(:tcp, listener, owner, responder)

      {:error, :closed} ->
        :ok

      {:error, reason} ->
        send(owner, {:web_fetch_server_error, reason})
    end
  end

  defp accept_loop(:ssl, listener, owner, responder) do
    case :ssl.transport_accept(listener) do
      {:ok, transport_socket} ->
        case :ssl.handshake(transport_socket, 5_000) do
          {:ok, socket} -> serve(:ssl, socket, owner, responder)
          {:error, reason} -> send(owner, {:web_fetch_server_error, reason})
        end

        accept_loop(:ssl, listener, owner, responder)

      {:error, :closed} ->
        :ok

      {:error, reason} ->
        send(owner, {:web_fetch_server_error, reason})
    end
  end

  defp serve(transport, socket, owner, responder) do
    with {:ok, raw_request} <- receive_request(transport, socket),
         {:ok, request} <- parse_request(raw_request) do
      send(owner, {:web_fetch_server_request, self(), request})

      case responder.(request) do
        :close -> :ok
        :reset -> reset_socket(transport, socket)
        response -> send_response(transport, socket, owner, response)
      end
    else
      {:error, reason} -> send(owner, {:web_fetch_server_error, reason})
    end

    close_socket(transport, socket)
  end

  defp receive_request(transport, socket), do: receive_request(transport, socket, "")

  defp receive_request(transport, socket, received) do
    if complete_request?(received) do
      {:ok, received}
    else
      case receive_socket(transport, socket) do
        {:ok, data} -> receive_request(transport, socket, received <> data)
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp receive_socket(:tcp, socket), do: :gen_tcp.recv(socket, 0, 5_000)
  defp receive_socket(:ssl, socket), do: :ssl.recv(socket, 0, 5_000)

  defp complete_request?(received) do
    case String.split(received, "\r\n\r\n", parts: 2) do
      [headers, body] -> byte_size(body) >= content_length(headers)
      [_headers] -> false
    end
  end

  defp content_length(headers) do
    headers
    |> String.split("\r\n")
    |> Enum.find_value(0, &content_length_line/1)
  end

  defp content_length_line(line) do
    case String.split(line, ":", parts: 2) do
      [name, value] ->
        if String.downcase(name) == "content-length", do: value |> String.trim() |> String.to_integer()

      _other ->
        nil
    end
  end

  defp parse_request(raw_request) do
    [head, body] = String.split(raw_request, "\r\n\r\n", parts: 2)
    [request_line | header_lines] = String.split(head, "\r\n", trim: true)

    case String.split(request_line, " ") do
      [method, path, _version] ->
        headers =
          Map.new(header_lines, fn line ->
            [name, value] = String.split(line, ":", parts: 2)
            {String.downcase(name), String.trim(value)}
          end)

        {:ok, %{body: body, method: method, path: path, headers: headers}}

      _other ->
        {:error, :invalid_request_line}
    end
  end

  defp send_response(transport, socket, owner, %{status: status} = response) do
    framing = Map.get(response, :framing, :content_length)
    chunks = Map.get(response, :chunks, [Map.get(response, :body, "")])

    headers =
      response
      |> Map.get(:headers, [])
      |> put_new_header("content-type", "text/plain")
      |> response_framing_headers(response, chunks, framing)
      |> put_header("connection", "close")

    head = [
      "HTTP/1.1 #{status} #{status_reason(status)}\r\n",
      Enum.map(headers, fn {name, value} -> "#{name}: #{value}\r\n" end),
      "\r\n"
    ]

    case send_socket(transport, socket, head) do
      :ok -> send_response_chunks(transport, socket, owner, chunks, framing, response)
      {:error, _reason} = error -> error
    end
  end

  defp response_framing_headers(headers, response, chunks, :content_length) do
    declared_content_length =
      Map.get_lazy(response, :declared_content_length, fn ->
        chunks |> Enum.map(&IO.iodata_length/1) |> Enum.sum()
      end)

    headers
    |> delete_header("transfer-encoding")
    |> put_header("content-length", Integer.to_string(declared_content_length))
  end

  defp response_framing_headers(headers, _response, _chunks, :chunked) do
    headers
    |> delete_header("content-length")
    |> put_header("transfer-encoding", "chunked")
  end

  defp response_framing_headers(headers, _response, _chunks, :close) do
    headers
    |> delete_header("content-length")
    |> delete_header("transfer-encoding")
  end

  defp send_response_chunks(transport, socket, owner, chunks, framing, response) do
    delay_ms = Map.get(response, :chunk_delay_ms, 0)

    result =
      chunks
      |> Stream.with_index()
      |> Enum.reduce_while(:ok, fn {chunk, index}, :ok ->
        if delay_ms > 0, do: Process.sleep(delay_ms)

        payload = encode_response_chunk(chunk, framing)
        result = send_socket(transport, socket, payload)
        send(owner, {:web_fetch_server_chunk, self(), index, IO.iodata_length(chunk), result})

        case result do
          :ok -> {:cont, :ok}
          {:error, _reason} -> {:halt, result}
        end
      end)

    if result == :ok and framing == :chunked do
      send_socket(transport, socket, "0\r\n\r\n")
    else
      result
    end
  end

  defp encode_response_chunk(chunk, :chunked) do
    [Integer.to_string(IO.iodata_length(chunk), 16), "\r\n", chunk, "\r\n"]
  end

  defp encode_response_chunk(chunk, _framing), do: chunk

  defp send_socket(:tcp, socket, payload), do: :gen_tcp.send(socket, payload)
  defp send_socket(:ssl, socket, payload), do: :ssl.send(socket, payload)

  defp status_reason(200), do: "OK"
  defp status_reason(301), do: "Moved Permanently"
  defp status_reason(302), do: "Found"
  defp status_reason(303), do: "See Other"
  defp status_reason(307), do: "Temporary Redirect"
  defp status_reason(308), do: "Permanent Redirect"
  defp status_reason(_status), do: "Response"

  defp address_family_options({_a, _b, _c, _d}), do: [:inet]

  defp address_family_options({_a, _b, _c, _d, _e, _f, _g, _h}) do
    [:inet6, ipv6_v6only: true]
  end

  defp close_socket(:tcp, socket), do: :gen_tcp.close(socket)
  defp close_socket(:ssl, socket), do: :ssl.close(socket)

  defp reset_socket(:tcp, socket) do
    :inet.setopts(socket, linger: {true, 0})
    :gen_tcp.close(socket)
  end

  defp reset_socket(:ssl, socket), do: :ssl.close(socket)

  defp put_new_header(headers, name, value) do
    if List.keymember?(headers, name, 0), do: headers, else: [{name, value} | headers]
  end

  defp put_header(headers, name, value), do: List.keystore(headers, name, 0, {name, value})

  defp delete_header(headers, name), do: List.keydelete(headers, name, 0)

  defp fixture_path(filename) do
    __DIR__
    |> Path.join("../fixtures/web_fetch")
    |> Path.join(filename)
    |> Path.expand()
    |> String.to_charlist()
  end

  defp stop_process(pid) do
    if Process.alive?(pid), do: Process.exit(pid, :kill)
    :ok
  end
end
