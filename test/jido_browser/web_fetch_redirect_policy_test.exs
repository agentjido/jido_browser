defmodule Jido.Browser.WebFetchRedirectPolicyTest do
  use ExUnit.Case, async: false

  alias Jido.Browser.Error.{AdapterError, InvalidError}
  alias Jido.Browser.TestSupport.WebFetchServer
  alias Jido.Browser.WebFetch

  @invalid_redirect_locations [
    "http://fixture.test:65536/next",
    "http://fixture.test:0/next",
    "http://fixture.test:abc/next",
    "/bad%2",
    "/bad%GG",
    "/next?credential=%GG",
    "/bad%0Dpath",
    "/bad path",
    "http:///missing",
    "http://[",
    "http://bad..test/next",
    "file:///etc/passwd",
    "http://user:secret@fixture.test/private",
    "http:relative",
    "//",
    "\\evil.test/path"
  ]

  setup do
    WebFetch.clear_cache()
    :ok
  end

  test "validates and follows relative and absolute redirects and preserves the final URL" do
    final_server = WebFetchServer.start_http(self(), &ok_response/1)

    redirect_server =
      WebFetchServer.start_http(self(), fn
        %{path: "/start"} -> redirect_response("/middle?step=relative")
        %{path: "/middle?step=relative"} -> redirect_response("http://fixture.test:#{final_server.port}/final")
      end)

    on_exit(fn ->
      WebFetchServer.stop(redirect_server)
      WebFetchServer.stop(final_server)
    end)

    assert {:ok, result} = fetch_local(redirect_server, "/start")
    assert result.content == "redirect target"
    assert result.final_url == "http://fixture.test:#{final_server.port}/final"

    assert_receive {:web_fetch_server_request, redirect_pid, %{path: "/start"}}
    assert redirect_pid == redirect_server.pid
    assert_receive {:web_fetch_server_request, ^redirect_pid, %{path: "/middle?step=relative"}}
    assert_receive {:web_fetch_server_request, final_pid, %{path: "/final"}}
    assert final_pid == final_server.pid
  end

  test "applies blocked_domains before an absolute redirect request" do
    blocked_server = WebFetchServer.start_http(self(), &ok_response/1)

    source_server =
      WebFetchServer.start_http(self(), fn _request ->
        redirect_response("http://blocked.test:#{blocked_server.port}/private")
      end)

    on_exit(fn ->
      WebFetchServer.stop(source_server)
      WebFetchServer.stop(blocked_server)
    end)

    assert {:error, %InvalidError{details: %{error_code: :url_not_allowed}}} =
             fetch_local(source_server, "/start", blocked_domains: ["blocked.test"])

    assert_receive {:web_fetch_server_request, source_pid, %{path: "/start"}}
    assert source_pid == source_server.pid
    blocked_pid = blocked_server.pid
    refute_receive {:web_fetch_server_request, ^blocked_pid, _request}
  end

  test "removes Req credentials when a redirect changes the effective port" do
    target_server = WebFetchServer.start_http(self(), &ok_response/1)

    source_server =
      WebFetchServer.start_http(self(), fn _request ->
        redirect_response("http://fixture.test:#{target_server.port}/target")
      end)

    on_exit(fn ->
      WebFetchServer.stop(source_server)
      WebFetchServer.stop(target_server)
    end)

    assert {:ok, _result} =
             fetch_local(source_server, "/start",
               req: [
                 retry: false,
                 auth: {:bearer, "option-secret"},
                 headers: [{"authorization", "Bearer header-secret"}]
               ]
             )

    assert_receive {:web_fetch_server_request, source_pid, source_request}
    assert source_pid == source_server.pid
    assert source_request.headers["authorization"] == "Bearer option-secret"

    assert_receive {:web_fetch_server_request, target_pid, target_request}
    assert target_pid == target_server.pid
    refute Map.has_key?(target_request.headers, "authorization")
  end

  test "removes Req credentials, AWS signing, cookies, and query data across origins" do
    target_server = WebFetchServer.start_http(self(), &ok_response/1)

    source_server =
      WebFetchServer.start_http(self(), fn _request ->
        redirect_response("http://fixture.test:#{target_server.port}/target")
      end)

    on_exit(fn ->
      WebFetchServer.stop(source_server)
      WebFetchServer.stop(target_server)
    end)

    assert {:ok, _result} =
             fetch_local(source_server, "/start",
               req: [
                 retry: false,
                 auth: {:bearer, "auth-option-secret"},
                 aws_sigv4: [
                   access_key_id: "AKIDEXAMPLE",
                   secret_access_key: "aws-secret",
                   token: "session-token-secret",
                   service: :s3,
                   region: "us-east-1",
                   datetime: ~U[2026-08-27 12:00:00Z]
                 ],
                 params: [api_key: "query-secret"],
                 headers: [
                   {"AuThOrIzAtIoN", "Bearer header-secret"},
                   {"PrOxY-AuThOrIzAtIoN", "Basic proxy-secret"},
                   {"CoOkIe", "manual=session-secret"}
                 ]
               ]
             )

    assert_receive {:web_fetch_server_request, source_pid, source_request}
    assert source_pid == source_server.pid
    assert source_request.path == "/start?api_key=query-secret"
    assert String.starts_with?(source_request.headers["authorization"], "AWS4-HMAC-SHA256")
    assert source_request.headers["proxy-authorization"] == "Basic proxy-secret"
    assert source_request.headers["cookie"] == "manual=session-secret"
    assert source_request.headers["x-amz-security-token"] == "session-token-secret"

    assert_receive {:web_fetch_server_request, target_pid, target_request}
    assert target_pid == target_server.pid
    assert target_request.path == "/target"

    for header <- ["authorization", "proxy-authorization", "cookie", "x-amz-security-token"] do
      refute Map.has_key?(target_request.headers, header)
    end

    refute Enum.any?(Map.keys(target_request.headers), &String.starts_with?(&1, "x-amz-"))
    refute target_request.path =~ "query-secret"
  end

  test "matches Req POST redirect method and body rules on the same origin" do
    for status <- [301, 302, 303, 307, 308] do
      server =
        WebFetchServer.start_http(self(), fn
          %{path: "/start"} -> redirect_response("/target", status)
          %{path: "/target"} -> ok_response(nil)
        end)

      try do
        body = "side-effect=#{status}"

        assert {:ok, _result} =
                 fetch_local(server, "/start",
                   req: [
                     retry: false,
                     method: :post,
                     body: body,
                     headers: [
                       {"content-length", Integer.to_string(byte_size(body))},
                       {"content-type", "application/x-www-form-urlencoded"}
                     ]
                   ]
                 )

        assert_receive {:web_fetch_server_request, server_pid, source_request}
        assert server_pid == server.pid
        assert source_request.method == "POST"
        assert source_request.body == body

        assert_receive {:web_fetch_server_request, ^server_pid, target_request}

        if status in [301, 302, 303] do
          assert target_request.method == "GET"
          assert target_request.body == ""
          refute Map.has_key?(target_request.headers, "content-length")
          refute Map.has_key?(target_request.headers, "content-type")
        else
          assert target_request.method == "POST"
          assert target_request.body == body
          assert target_request.headers["content-length"] == Integer.to_string(byte_size(body))
          assert target_request.headers["content-type"] == "application/x-www-form-urlencoded"
        end
      after
        WebFetchServer.stop(server)
      end
    end
  end

  test "applies method rules before cross-origin credential cleanup" do
    for status <- [302, 307] do
      target_server = WebFetchServer.start_http(self(), &ok_response/1)

      source_server =
        WebFetchServer.start_http(self(), fn _request ->
          redirect_response("http://fixture.test:#{target_server.port}/target", status)
        end)

      try do
        body = "cross-origin=#{status}"

        assert {:ok, _result} =
                 fetch_local(source_server, "/start",
                   req: [
                     retry: false,
                     method: :post,
                     body: body,
                     auth: {:bearer, "cross-origin-secret"},
                     headers: [
                       {"cookie", "session=cross-origin-secret"},
                       {"content-length", Integer.to_string(byte_size(body))},
                       {"content-type", "application/x-www-form-urlencoded"}
                     ]
                   ]
                 )

        assert_receive {:web_fetch_server_request, source_pid, source_request}
        assert source_pid == source_server.pid
        assert source_request.method == "POST"
        assert source_request.body == body
        assert source_request.headers["authorization"] == "Bearer cross-origin-secret"
        assert source_request.headers["cookie"] == "session=cross-origin-secret"

        assert_receive {:web_fetch_server_request, target_pid, target_request}
        assert target_pid == target_server.pid
        refute Map.has_key?(target_request.headers, "authorization")
        refute Map.has_key?(target_request.headers, "cookie")

        if status == 302 do
          assert target_request.method == "GET"
          assert target_request.body == ""
          refute Map.has_key?(target_request.headers, "content-length")
          refute Map.has_key?(target_request.headers, "content-type")
        else
          assert target_request.method == "POST"
          assert target_request.body == body
          assert target_request.headers["content-length"] == Integer.to_string(byte_size(body))
          assert target_request.headers["content-type"] == "application/x-www-form-urlencoded"
        end
      after
        WebFetchServer.stop(source_server)
        WebFetchServer.stop(target_server)
      end
    end
  end

  test "does not rewrite HEAD across any supported redirect status" do
    for status <- [301, 302, 303, 307, 308] do
      server =
        WebFetchServer.start_http(self(), fn
          %{path: "/start"} -> redirect_response("/target", status)
          %{path: "/target"} -> %{status: 200, body: ""}
        end)

      try do
        assert {:ok, _result} = fetch_local(server, "/start", req: [retry: false, method: :head])
        assert_receive {:web_fetch_server_request, server_pid, %{method: "HEAD", body: ""}}
        assert server_pid == server.pid
        assert_receive {:web_fetch_server_request, ^server_pid, %{method: "HEAD", body: ""}}
      after
        WebFetchServer.stop(server)
      end
    end
  end

  test "does not re-run Req body producers after a POST-to-GET redirect" do
    cases = [
      json: [json: %{secret: "json-secret"}],
      form: [form: [secret: "form-secret"]],
      form_multipart: [form_multipart: [secret: "multipart-secret"]]
    ]

    for {name, body_opts} <- cases do
      server =
        WebFetchServer.start_http(self(), fn
          %{path: "/start"} -> redirect_response("/target", 302)
          %{path: "/target"} -> ok_response(nil)
        end)

      try do
        assert {:ok, _result} =
                 fetch_local(server, "/start", req: Keyword.merge([retry: false, method: :post], body_opts))

        assert_receive {:web_fetch_server_request, server_pid, source_request}
        assert server_pid == server.pid
        assert source_request.method == "POST"
        assert source_request.body != ""

        assert_receive {:web_fetch_server_request, ^server_pid, target_request}
        assert target_request.method == "GET", "#{name} changed the redirect method"
        assert target_request.body == "", "#{name} was applied again"
        refute Map.has_key?(target_request.headers, "content-length")
        refute Map.has_key?(target_request.headers, "content-type")
      after
        WebFetchServer.stop(server)
      end
    end
  end

  test "keeps Req credentials on a same-origin redirect" do
    server =
      WebFetchServer.start_http(self(), fn
        %{path: "/start"} -> redirect_response("/target")
        %{path: "/target"} -> ok_response(nil)
      end)

    on_exit(fn -> WebFetchServer.stop(server) end)

    assert {:ok, _result} =
             fetch_local(server, "/start",
               req: [
                 retry: false,
                 auth: {:bearer, "same-origin-secret"},
                 headers: [
                   {"PrOxY-AuThOrIzAtIoN", "Basic same-origin-proxy"},
                   {"CoOkIe", "same-origin=cookie"}
                 ]
               ]
             )

    assert_receive {:web_fetch_server_request, server_pid, source_request}
    assert server_pid == server.pid
    assert source_request.headers["authorization"] == "Bearer same-origin-secret"

    assert_receive {:web_fetch_server_request, ^server_pid, target_request}
    assert target_request.headers["authorization"] == "Bearer same-origin-secret"
    assert target_request.headers["proxy-authorization"] == "Basic same-origin-proxy"
    assert target_request.headers["cookie"] == "same-origin=cookie"
  end

  test "Req uses the stable policy code before requests to strict invalid redirect targets" do
    for location <- @invalid_redirect_locations do
      server = WebFetchServer.start_http(self(), fn _request -> redirect_response(location) end)

      try do
        assert {:error, %InvalidError{details: details}} = fetch_local(server, "/start")
        assert details.error_code == :url_not_allowed
        assert_receive {:web_fetch_server_request, server_pid, %{path: "/start"}}
        assert server_pid == server.pid
        refute_receive {:web_fetch_server_request, ^server_pid, _request}
      after
        WebFetchServer.stop(server)
      end
    end
  end

  test "Req uses the stable policy code for missing and empty Location headers" do
    for response <- [
          %{status: 302, headers: [], body: ""},
          %{status: 302, headers: [{"location", ""}], body: ""}
        ] do
      server = WebFetchServer.start_http(self(), fn _request -> response end)

      try do
        assert {:error, %InvalidError{details: details}} = fetch_local(server, "/start")
        assert details.error_code == :url_not_allowed
        assert_receive {:web_fetch_server_request, server_pid, %{path: "/start"}}
        assert server_pid == server.pid
      after
        WebFetchServer.stop(server)
      end
    end
  end

  test "Req accepts a valid parent relative redirect with escaped query data" do
    server =
      WebFetchServer.start_http(self(), fn
        %{path: "/dir/start"} -> redirect_response("../target?value=%2F")
        %{path: "/target?value=%2F"} -> ok_response(nil)
      end)

    on_exit(fn -> WebFetchServer.stop(server) end)

    assert {:ok, req_result} = fetch_local(server, "/dir/start")
    assert req_result.final_url == "http://fixture.test:#{server.port}/target?value=%2F"
  end

  test "keeps a nested Req redirect limit and does not request the next target" do
    server =
      WebFetchServer.start_http(self(), fn
        %{path: "/one"} -> redirect_response("/two")
        %{path: "/two"} -> redirect_response("/three")
        %{path: "/three"} -> ok_response(nil)
      end)

    on_exit(fn -> WebFetchServer.stop(server) end)

    assert {:error, %AdapterError{details: details}} =
             fetch_local(server, "/one", req: [retry: false, max_redirects: 1])

    assert details.error_code == :url_not_accessible
    assert details.max_redirects == 1
    assert_receive {:web_fetch_server_request, server_pid, %{path: "/one"}}
    assert server_pid == server.pid
    assert_receive {:web_fetch_server_request, ^server_pid, %{path: "/two"}}
    refute_receive {:web_fetch_server_request, ^server_pid, %{path: "/three"}}
  end

  test "gives an explicit top-level redirect limit precedence over the nested Req limit" do
    server =
      WebFetchServer.start_http(self(), fn
        %{path: "/one"} -> redirect_response("/two")
        %{path: "/two"} -> redirect_response("/three")
        %{path: "/three"} -> redirect_response("/four")
        %{path: "/four"} -> ok_response(nil)
      end)

    on_exit(fn -> WebFetchServer.stop(server) end)

    assert {:error, %AdapterError{details: details}} =
             fetch_local(server, "/one",
               max_redirects: 2,
               req: [retry: false, max_redirects: 1]
             )

    assert details.max_redirects == 2
    assert_receive {:web_fetch_server_request, server_pid, %{path: "/one"}}
    assert_receive {:web_fetch_server_request, ^server_pid, %{path: "/two"}}
    assert_receive {:web_fetch_server_request, ^server_pid, %{path: "/three"}}
    refute_receive {:web_fetch_server_request, ^server_pid, %{path: "/four"}}
  end

  test "uses Req's compatible default redirect limit of ten" do
    server =
      WebFetchServer.start_http(self(), fn %{path: "/" <> index} ->
        redirect_response("/#{String.to_integer(index) + 1}")
      end)

    on_exit(fn -> WebFetchServer.stop(server) end)

    assert {:error, %AdapterError{details: details}} = fetch_local(server, "/0")
    assert details.max_redirects == 10

    for index <- 0..10 do
      path = "/#{index}"
      assert_receive {:web_fetch_server_request, server_pid, %{path: ^path}}
      assert server_pid == server.pid
    end

    refute_receive {:web_fetch_server_request, _server_pid, %{path: "/11"}}
  end

  defp fetch_local(server, path, opts \\ []) do
    resolver = fn host ->
      assert host in ["fixture.test", "blocked.test"]
      {:ok, [{127, 0, 0, 1}]}
    end

    request_opts =
      Keyword.merge(
        [
          allow_private_network: true,
          cache: false,
          format: :text,
          req: [retry: false],
          resolver: resolver
        ],
        opts
      )

    Jido.Browser.web_fetch("http://fixture.test:#{server.port}#{path}", request_opts)
  end

  defp redirect_response(location, status \\ 302) do
    %{status: status, headers: [{"location", location}], body: ""}
  end

  defp ok_response(_request) do
    %{status: 200, body: "redirect target"}
  end
end
