defmodule JidoBrowser.TestSupport.IntegrationTestServer do
  @moduledoc false

  @type server :: %{
          listener: :gen_tcp.socket(),
          acceptor: pid(),
          port: non_neg_integer()
        }

  @doc """
  Starts a local HTTP fixture server on a random localhost port.
  """
  @spec start() :: {:ok, server()}
  def start do
    listen_opts = [
      :binary,
      {:active, false},
      {:packet, :raw},
      {:reuseaddr, true},
      {:ip, {127, 0, 0, 1}}
    ]

    with {:ok, listener} <- :gen_tcp.listen(0, listen_opts),
         {:ok, {_, port}} <- :inet.sockname(listener),
         {:ok, acceptor} <- Task.start_link(fn -> accept_loop(listener) end) do
      {:ok, %{listener: listener, acceptor: acceptor, port: port}}
    end
  end

  @doc """
  Stops a running fixture server.
  """
  @spec stop(server()) :: :ok
  def stop(%{listener: listener, acceptor: acceptor}) do
    :gen_tcp.close(listener)
    Process.exit(acceptor, :normal)
    :ok
  end

  @doc """
  Returns the base URL for a running fixture server.
  """
  @spec base_url(server()) :: String.t()
  def base_url(%{port: port}), do: "http://127.0.0.1:#{port}"

  @doc """
  Returns a localhost URL that should refuse connections for error-path tests.
  """
  @spec unreachable_url() :: String.t()
  def unreachable_url do
    opts = [:binary, {:active, false}, {:packet, :raw}, {:ip, {127, 0, 0, 1}}]

    {:ok, listener} = :gen_tcp.listen(0, opts)
    {:ok, {_, port}} = :inet.sockname(listener)
    :gen_tcp.close(listener)
    "http://127.0.0.1:#{port}/unreachable"
  end

  defp accept_loop(listener) do
    case :gen_tcp.accept(listener) do
      {:ok, socket} ->
        Task.start(fn -> handle_connection(socket) end)
        accept_loop(listener)

      {:error, :closed} ->
        :ok

      {:error, _reason} ->
        :ok
    end
  end

  defp handle_connection(socket) do
    response =
      case read_request(socket, "") do
        {:ok, request} ->
          request
          |> request_path()
          |> response_for_path()
          |> build_response()

        {:error, _reason} ->
          build_response({"400 Bad Request", "<html><body>Bad Request</body></html>"})
      end

    :ok = :gen_tcp.send(socket, response)
    :gen_tcp.close(socket)
  end

  defp read_request(socket, acc) do
    if String.contains?(acc, "\r\n\r\n") do
      {:ok, acc}
    else
      case :gen_tcp.recv(socket, 0, 1000) do
        {:ok, chunk} ->
          read_request(socket, acc <> chunk)

        {:error, :timeout} ->
          {:ok, acc}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp request_path(request) do
    request_line = request |> String.split("\r\n", parts: 2) |> List.first("")

    case String.split(request_line, " ", parts: 3) do
      [_method, target, _version] ->
        URI.parse(target).path || "/"

      _ ->
        "/"
    end
  end

  defp response_for_path("/") do
    {"200 OK",
     """
     <!DOCTYPE html>
     <html>
       <head><title>Integration Test Home</title></head>
       <body>
         <h1>Integration Test Home</h1>
         <p>This page is served from a local fixture server.</p>
         <a id="next-link" href="/next">Next Page</a>
         <form>
           <label for="search-input">Search</label>
           <input id="search-input" name="q" type="text" />
         </form>
       </body>
     </html>
     """}
  end

  defp response_for_path("/next") do
    {"200 OK",
     """
     <!DOCTYPE html>
     <html>
       <head><title>Integration Test Next</title></head>
       <body>
         <h1>Integration Test Next</h1>
         <p>Second page used for click navigation tests.</p>
       </body>
     </html>
     """}
  end

  defp response_for_path("/article") do
    {"200 OK",
     """
     <!DOCTYPE html>
     <html>
       <head><title>Integration Test Article</title></head>
       <body>
         <article>
           <h1>Deterministic Fixture Content</h1>
           <p>Used for markdown extraction assertions in integration tests.</p>
         </article>
       </body>
     </html>
     """}
  end

  defp response_for_path(_) do
    {"404 Not Found",
     """
     <!DOCTYPE html>
     <html>
       <head><title>Not Found</title></head>
       <body><h1>404 Not Found</h1></body>
     </html>
     """}
  end

  defp build_response({status, body}) do
    [
      "HTTP/1.1 ",
      status,
      "\r\n",
      "content-type: text/html; charset=utf-8\r\n",
      "content-length: ",
      Integer.to_string(byte_size(body)),
      "\r\n",
      "connection: close\r\n",
      "\r\n",
      body
    ]
  end
end
