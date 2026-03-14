defmodule Jido.Browser.TestSupport.IntegrationTestServer do
  @moduledoc false

  require Logger

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

    case :gen_tcp.send(socket, response) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.debug("Integration fixture response send skipped: #{inspect(reason)}")
    end

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
        <article data-testid="fixture-article">
           <h1>Deterministic Fixture Content</h1>
           <p>Used for markdown extraction assertions in integration tests.</p>
         </article>
       </body>
     </html>
     """}
  end

  defp response_for_path("/refs") do
    {"200 OK",
     """
     <!DOCTYPE html>
     <html>
       <head><title>Ref Interaction Fixture</title></head>
       <body>
         <h1>Ref Interaction Fixture</h1>
         <p>Used to validate snapshot refs and ref-based interaction.</p>
         <label for="ref-input">Ref Input Marker</label>
         <input
           id="ref-input"
           name="ref_input"
           type="text"
           aria-label="Ref Input Marker"
           placeholder="Ref Input Marker"
         />
         <button id="ref-button" type="button">Use Ref Button Marker</button>
         <div id="ref-output" role="status">Idle</div>
         <script>
           document.getElementById("ref-button").addEventListener("click", function () {
             const value = document.getElementById("ref-input").value || "empty";
             document.getElementById("ref-output").textContent = "Submitted: " + value;
           });
         </script>
       </body>
     </html>
     """}
  end

  defp response_for_path("/dynamic") do
    {"200 OK",
     """
     <!DOCTYPE html>
     <html>
       <head><title>Dynamic Wait Fixture</title></head>
       <body>
         <h1>Dynamic Wait Fixture</h1>
         <div id="wait-status">Waiting for delayed content</div>
         <script>
           window.setTimeout(function () {
             const div = document.createElement("div");
             div.id = "ready-message";
             div.textContent = "Dynamic content ready";
             document.body.appendChild(div);
             document.getElementById("wait-status").textContent = "Ready";
           }, 300);
         </script>
       </body>
     </html>
     """}
  end

  defp response_for_path("/delayed-navigation") do
    {"200 OK",
     """
     <!DOCTYPE html>
     <html>
       <head><title>Delayed Navigation Fixture</title></head>
       <body>
         <h1>Delayed Navigation Fixture</h1>
         <button id="go-next" type="button">Delayed Next Marker</button>
         <script>
           document.getElementById("go-next").addEventListener("click", function () {
             window.setTimeout(function () {
               window.location.href = "/next";
             }, 300);
           });
         </script>
       </body>
     </html>
     """}
  end

  defp response_for_path("/state") do
    {"200 OK",
     """
     <!DOCTYPE html>
     <html>
       <head><title>State Persistence Fixture</title></head>
       <body>
         <h1>State Persistence Fixture</h1>
         <label for="state-name">State Name Marker</label>
         <input id="state-name" name="state_name" type="text" />
         <button id="save-state" type="button">Persist State Marker</button>
         <p id="current-state" role="status"></p>
         <script>
           function renderSavedName() {
             const current = localStorage.getItem("saved_name") || "anonymous";
             document.getElementById("current-state").textContent = current;
           }

           document.getElementById("save-state").addEventListener("click", function () {
             const value = document.getElementById("state-name").value || "anonymous";
             localStorage.setItem("saved_name", value);
             renderSavedName();
           });

           renderSavedName();
         </script>
       </body>
     </html>
     """}
  end

  defp response_for_path("/console-and-errors") do
    {"200 OK",
     """
     <!DOCTYPE html>
     <html>
       <head><title>Console And Errors Fixture</title></head>
       <body>
         <h1>Console And Errors Fixture</h1>
         <p>Used to validate browser diagnostics collection.</p>
         <script>
           window.addEventListener("load", function () {
             console.log("fixture-console-ready");
             console.info("fixture-console-info");

             window.setTimeout(function () {
               console.error("fixture-console-error");
             }, 50);

             window.setTimeout(function () {
               throw new Error("fixture-page-error");
             }, 100);
           });
         </script>
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
