defmodule Jido.Browser.WebFetchDestinationPolicyTest do
  use ExUnit.Case, async: false

  alias Jido.Browser.Error.{AdapterError, InvalidError}
  alias Jido.Browser.TestSupport.WebFetchServer
  alias Jido.Browser.WebFetch
  alias Jido.Browser.WebFetch.Backends.Req, as: ReqBackend
  alias Jido.Browser.WebFetch.Backends.Req.PinnedFinch

  @blocked_urls [
    "http://0.0.0.0",
    "http://127.0.0.1",
    "http://10.0.0.1",
    "http://172.16.0.1",
    "http://192.168.0.1",
    "http://169.254.169.254",
    "http://100.100.100.200",
    "http://[::]",
    "http://[::1]",
    "http://[fc00::1]",
    "http://[fe80::1]",
    "http://[fd00:ec2::254]"
  ]
  @special_address_boundaries [
    {"0.0.0.0", :this_network},
    {"0.255.255.255", :this_network},
    {"10.0.0.0", :private},
    {"10.255.255.255", :private},
    {"100.64.0.0", :shared_address_space},
    {"100.127.255.255", :shared_address_space},
    {"127.0.0.0", :loopback},
    {"127.255.255.255", :loopback},
    {"169.254.0.0", :link_local},
    {"169.254.255.255", :link_local},
    {"172.16.0.0", :private},
    {"172.31.255.255", :private},
    {"192.0.0.0", :special_use},
    {"192.0.0.255", :special_use},
    {"192.0.2.0", :documentation},
    {"192.0.2.255", :documentation},
    {"192.31.196.0", :special_use},
    {"192.31.196.255", :special_use},
    {"192.52.193.0", :special_use},
    {"192.52.193.255", :special_use},
    {"192.88.99.0", :special_use},
    {"192.88.99.255", :special_use},
    {"192.168.0.0", :private},
    {"192.168.255.255", :private},
    {"192.175.48.0", :special_use},
    {"192.175.48.255", :special_use},
    {"198.18.0.0", :benchmarking},
    {"198.19.255.255", :benchmarking},
    {"198.51.100.0", :documentation},
    {"198.51.100.255", :documentation},
    {"203.0.113.0", :documentation},
    {"203.0.113.255", :documentation},
    {"224.0.0.0", :multicast},
    {"239.255.255.255", :multicast},
    {"240.0.0.0", :reserved},
    {"255.255.255.255", :reserved},
    {"::", :unspecified},
    {"::1", :loopback},
    {"::ffff:0.0.0.0", :ipv4_mapped},
    {"::ffff:255.255.255.255", :ipv4_mapped},
    {"64:ff9b::", :translation},
    {"64:ff9b::ffff:ffff", :translation},
    {"64:ff9b:1::", :translation},
    {"64:ff9b:1:ffff:ffff:ffff:ffff:ffff", :translation},
    {"100::", :discard_only},
    {"100::ffff:ffff:ffff:ffff", :discard_only},
    {"100:0:0:1::", :special_use},
    {"100:0:0:1:ffff:ffff:ffff:ffff", :special_use},
    {"2001::", :special_use},
    {"2001:1ff:ffff:ffff:ffff:ffff:ffff:ffff", :special_use},
    {"2001:db8::", :documentation},
    {"2001:db8:ffff:ffff:ffff:ffff:ffff:ffff", :documentation},
    {"2002::", :special_use},
    {"2002:ffff:ffff:ffff:ffff:ffff:ffff:ffff", :special_use},
    {"2620:4f:8000::", :special_use},
    {"2620:4f:8000:ffff:ffff:ffff:ffff:ffff", :special_use},
    {"3fff::", :documentation},
    {"3fff:fff:ffff:ffff:ffff:ffff:ffff:ffff", :documentation},
    {"5f00::", :special_use},
    {"5f00:ffff:ffff:ffff:ffff:ffff:ffff:ffff", :special_use},
    {"fc00::", :private},
    {"fdff:ffff:ffff:ffff:ffff:ffff:ffff:ffff", :private},
    {"fe80::", :link_local},
    {"febf:ffff:ffff:ffff:ffff:ffff:ffff:ffff", :link_local},
    {"ff00::", :multicast},
    {"ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff", :multicast},
    {"4000::", :non_global},
    {"7fff:ffff:ffff:ffff:ffff:ffff:ffff:ffff", :non_global}
  ]

  setup do
    WebFetch.clear_cache()
    :ok
  end

  test "blocks direct IPv4, IPv6, and cloud metadata destinations with one policy code" do
    for url <- @blocked_urls do
      assert {:error, %InvalidError{details: details}} =
               Jido.Browser.web_fetch(url, cache: false)

      assert details.error_code == :url_not_allowed
      assert is_atom(details.policy_reason)
    end
  end

  test "blocks every IANA and global-routability classification boundary" do
    for {address_text, reason} <- @special_address_boundaries do
      {:ok, address} = :inet.parse_address(String.to_charlist(address_text))
      resolver = fn "boundary.test" -> {:ok, [address]} end

      assert {:error, %InvalidError{details: details}} =
               Jido.Browser.web_fetch("http://boundary.test", cache: false, resolver: resolver)

      assert details.error_code == :url_not_allowed
      assert details.policy_reason == reason
    end
  end

  test "blocks unsafe hostname answers, mapped addresses, and mixed multi-address answers" do
    cases = [
      {{:ok, [{127, 0, 0, 1}]}, :loopback},
      {{:ok, [{0, 0, 0, 0, 0, 0xFFFF, 0x7F00, 1}]}, :ipv4_mapped},
      {{:ok, [{93, 184, 216, 34}, {10, 0, 0, 8}]}, :private}
    ]

    for {resolver_result, reason} <- cases do
      resolver = fn "public.test" -> resolver_result end

      assert {:error, %InvalidError{details: details}} =
               Jido.Browser.web_fetch("http://public.test", cache: false, resolver: resolver)

      assert details.error_code == :url_not_allowed
      assert details.policy_reason == reason
    end
  end

  test "blocks alternate IPv4 literal encodings after resolution" do
    resolver = fn host ->
      assert host in ["2130706433", "0177.0.0.1", "0x7f000001"]
      {:ok, [{127, 0, 0, 1}]}
    end

    for host <- ["2130706433", "0177.0.0.1", "0x7f000001"] do
      assert {:error, %InvalidError{details: %{error_code: :url_not_allowed, policy_reason: :loopback}}} =
               Jido.Browser.web_fetch("http://#{host}", cache: false, resolver: resolver)
    end
  end

  test "returns the stable policy code when resolution fails" do
    resolver = fn "missing.test" -> {:error, :nxdomain} end

    assert {:error, %InvalidError{details: details}} =
             Jido.Browser.web_fetch("https://missing.test", cache: false, resolver: resolver)

    assert details.error_code == :url_not_allowed
    assert details.reason == :nxdomain
  end

  test "uses the explicit opt-in and pins an HTTP hostname to the resolved address" do
    attach_connect_observer()
    server = WebFetchServer.start_http(self(), &ok_response/1)
    on_exit(fn -> WebFetchServer.stop(server) end)

    assert {:ok, result} = fetch_local(server)
    assert result.content == "fixture response"
    assert result.final_url == "http://fixture.test:#{server.port}/content"

    assert_receive {:web_fetch_server_request, server_pid, request}
    assert server_pid == server.pid
    assert request.path == "/content"
    assert request.headers["host"] == "fixture.test:#{server.port}"
    assert_receive {:web_fetch_connect, %{host: {127, 0, 0, 1}, port: port}}
    assert port == server.port
  end

  test "pins HTTPS while Mint verifies the original hostname" do
    attach_connect_observer()
    server = WebFetchServer.start_https(self(), &ok_response/1)
    on_exit(fn -> WebFetchServer.stop(server) end)

    req_opts = [
      retry: false,
      connect_options: [transport_opts: [cacertfile: WebFetchServer.ca_certificate_path()]]
    ]

    assert {:ok, result} = fetch_local(server, req: req_opts)
    assert result.content == "fixture response"
    assert result.final_url == "https://fixture.test:#{server.port}/content"

    assert_receive {:web_fetch_server_request, server_pid, request}
    assert server_pid == server.pid
    assert request.headers["host"] == "fixture.test:#{server.port}"
    assert_receive {:web_fetch_connect, %{host: {127, 0, 0, 1}, port: port}}
    assert port == server.port
  end

  test "Req tries the next saved address after connection refusal" do
    attach_connect_observer()
    server = WebFetchServer.start_http(self(), &ok_response/1)
    on_exit(fn -> WebFetchServer.stop(server) end)
    Process.put(:refused_resolver_calls, 0)

    resolver = fn "fixture.test" ->
      Process.put(:refused_resolver_calls, Process.get(:refused_resolver_calls, 0) + 1)
      {:ok, [{0, 0, 0, 0, 0, 0, 0, 1}, {127, 0, 0, 1}]}
    end

    assert {:ok, result} =
             Jido.Browser.web_fetch("http://fixture.test:#{server.port}/content",
               allow_private_network: true,
               cache: false,
               format: :text,
               req: [retry: false],
               resolver: resolver
             )

    assert result.content == "fixture response"
    assert Process.get(:refused_resolver_calls) == 1
    assert_receive {:web_fetch_server_request, server_pid, request}
    assert server_pid == server.pid
    assert request.method == "GET"
    assert request.headers["host"] == "fixture.test:#{server.port}"

    assert_receive {:web_fetch_connect, %{host: {0, 0, 0, 0, 0, 0, 0, 1}}}
    assert_receive {:web_fetch_connect, %{host: {127, 0, 0, 1}}}
  end

  test "Req stops saved-address attempts after any HTTP response" do
    {first_server, second_server} =
      start_address_pair(fn _request -> %{status: 503, body: "service unavailable"} end)

    resolver = fn "fixture.test" -> {:ok, [first_server.ip, second_server.ip]} end

    assert {:error, %AdapterError{}} =
             Jido.Browser.web_fetch("http://fixture.test:#{first_server.port}/content",
               allow_private_network: true,
               cache: false,
               format: :text,
               req: [retry: false],
               resolver: resolver
             )

    assert_receive {:web_fetch_server_request, first_pid, %{method: "GET"}}
    assert first_pid == first_server.pid
    second_pid = second_server.pid
    refute_receive {:web_fetch_server_request, ^second_pid, _request}
  end

  test "Req does not retry a delivered POST after receive timeout" do
    {first_server, second_server} =
      start_address_pair(fn _request ->
        Process.sleep(150)
        ok_response(nil)
      end)

    Process.put(:timeout_resolver_calls, 0)

    resolver = fn "fixture.test" ->
      Process.put(:timeout_resolver_calls, Process.get(:timeout_resolver_calls, 0) + 1)
      {:ok, [first_server.ip, second_server.ip]}
    end

    assert {:error, %AdapterError{details: %{reason: %Req.TransportError{reason: :timeout}}}} =
             Jido.Browser.web_fetch("http://fixture.test:#{first_server.port}/charge",
               allow_private_network: true,
               cache: false,
               format: :text,
               req: [
                 retry: false,
                 method: :post,
                 body: "charge=once",
                 headers: [{"content-type", "application/x-www-form-urlencoded"}]
               ],
               resolver: resolver,
               timeout: 40
             )

    assert Process.get(:timeout_resolver_calls) == 1
    assert_receive {:web_fetch_server_request, first_pid, first_request}
    assert first_pid == first_server.pid
    assert first_request.method == "POST"
    assert first_request.body == "charge=once"
    second_pid = second_server.pid
    refute_receive {:web_fetch_server_request, ^second_pid, _request}
  end

  test "Req does not retry closed or reset connections after request delivery" do
    for action <- [:close, :reset] do
      {first_server, second_server} = start_address_pair(fn _request -> action end)
      resolver = fn "fixture.test" -> {:ok, [first_server.ip, second_server.ip]} end

      assert {:error, %AdapterError{details: %{reason: %Req.TransportError{reason: reason}}}} =
               Jido.Browser.web_fetch("http://fixture.test:#{first_server.port}/charge",
                 allow_private_network: true,
                 cache: false,
                 format: :text,
                 req: [retry: false, method: :post, body: "charge=#{action}"],
                 resolver: resolver
               )

      assert reason in [:closed, :econnreset]
      assert_receive {:web_fetch_server_request, first_pid, first_request}
      assert first_pid == first_server.pid
      assert first_request.method == "POST"
      assert first_request.body == "charge=#{action}"
      second_pid = second_server.pid
      refute_receive {:web_fetch_server_request, ^second_pid, _request}

      WebFetchServer.stop(first_server)
      WebFetchServer.stop(second_server)
    end
  end

  test "keeps a bracketed authority for a direct public IPv6 literal" do
    address = {0x2606, 0x4700, 0x4700, 0, 0, 0, 0, 0x1111}
    url = "https://[2606:4700:4700::1111]:8443/content"

    request_opts =
      ReqBackend.request_options(url,
        timeout: 1_000,
        req: [connect_options: [protocols: [:http2]]],
        destination_address: address
      )

    assert request_opts[:connect_options][:hostname] == "2606:4700:4700::1111"
    assert request_opts[:connect_options][:protocols] == [:http1]

    finch_request = request_opts |> Req.new() |> PinnedFinch.build_finch_request()

    assert finch_request.host == address
    assert {"host", "[2606:4700:4700::1111]:8443"} in finch_request.headers

    assert PinnedFinch.origin_authority(URI.parse("https://[2606:4700:4700::1111]/")) ==
             "[2606:4700:4700::1111]"
  end

  test "keeps domain rules active when private network access is enabled" do
    server = WebFetchServer.start_http(self(), &ok_response/1)
    on_exit(fn -> WebFetchServer.stop(server) end)

    assert {:error, %InvalidError{details: %{error_code: :url_not_allowed}}} =
             fetch_local(server, blocked_domains: ["fixture.test"])

    refute_receive {:web_fetch_server_request, _server_pid, _request}
  end

  defp fetch_local(server, opts \\ []) do
    resolver = fn "fixture.test" -> {:ok, [{127, 0, 0, 1}]} end
    url = "#{server.scheme}://fixture.test:#{server.port}/content"

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

    Jido.Browser.web_fetch(url, request_opts)
  end

  defp ok_response(_request) do
    %{status: 200, body: "fixture response"}
  end

  defp start_address_pair(first_responder) do
    first_server = WebFetchServer.start_http(self(), first_responder, ip: {0, 0, 0, 0, 0, 0, 0, 1})
    second_server = WebFetchServer.start_http(self(), &ok_response/1, ip: {127, 0, 0, 1}, port: first_server.port)

    on_exit(fn ->
      WebFetchServer.stop(first_server)
      WebFetchServer.stop(second_server)
    end)

    {first_server, second_server}
  end

  defp attach_connect_observer do
    handler_id = {__MODULE__, self(), make_ref()}

    :ok =
      :telemetry.attach(
        handler_id,
        [:finch, :connect, :start],
        fn _event, _measurements, metadata, owner ->
          send(owner, {:web_fetch_connect, metadata})
        end,
        self()
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)
  end
end
