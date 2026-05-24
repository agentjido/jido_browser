defmodule Jido.Browser.Vendor.BrowseyHttp do
  @moduledoc """
  Jido.Browser.Vendor.BrowseyHttp is a browser-imitating HTTP client for scraping websites that resist bot traffic.

  Browsey aims to behave as much like a real browser as possible, short of executing JavaScript.
  It's able to scrape sites that are notoriously difficult, including:

  - Amazon
  - Google
  - TicketMaster
  - LinkedIn (at least for the first few requests per day per IP, after which even real
    browsers will be shown the "auth wall")
  - Real estate sites including Zillow, Realtor.com, and Trulia
  - OpenSea
  - Sites protected by Cloudflare
  - Sites protected by PerimeterX/HUMAN Security
  - Sites protected by DataDome, including Reddit, AllTrails, and RealClearPolitics

  Plus, as a customer of Browsey, if you encounter a site Browsey can't scrape, we'll make
  a best effort attempt to get a fix for you. (Fully client-side rendered sites, though, will
  still not be supported.)

  Note that when scraping, you'll need to be mindful of both the IPs you're scraping from and
  how many requests you're sending to a given site. Too much traffic from a given IP will trip
  rate limits even if you *were* using a real browser. (For instance, if you try to scrape any
  major site within your CI system, it's almost guaranteed to fail. A shared IP on a cloud
  server is iffy as well.)

  ## Why Jido.Browser.Vendor.BrowseyHttp?

  ### Browsey versus other HTTP clients

  Because Browsey imitates a real browser beyond just faking a user agents, it is able to
  scrape *vastly* more sites than a default-configured HTTP client like HTTPoison, Finch,
  or Req, which get blocked by Cloudflare and other anti-bot measures.

  ### Browsey versus Selenium, Chromedriver, Playwright, etc.

  Running a real, headless web browser is the gold standard for fooling bot detection, and
  it's the *only* way to scrape sites that are fully client-side rendered. However, running
  a real browser is extremely resource-intensive; it's not uncommon to encounter a site that
  will cause Chromedriver to use 6 GB of RAM or more. Headless browsers are also quite a
  bit slower than Browsey, since you end up waiting for the page to render, execute
  JavaScript, etc.

  Worst of all, headless browsers can be unreliable. If you run a hundred requests, you'll
  encounter at least a few that fail in ways that aren't related to the site you're
  scraping having issues. Chromedriver may simply fail to respond to your commands for
  reasons that are impossible to diagnose. It may time out waiting for JavaScript to finish
  executing, and of course browsers can crash.

  In contrast, Browsey is extremely reliable (it's too simple to fail in complicated ways like
  browsers do!), and it requires virtually no resources beyond the memory needed to store
  the response data. It also has built-in protections to ensure memory usage doesn't
  spiral out of control (see the `:max_response_size_bytes` option to `Jido.Browser.Vendor.BrowseyHttp.get/2`).
  Finally, Browsey is quite a bit faster than a headless browser.

  ### Browsey versus a third-party scraping service like Zyte, ScrapeHero, or Apify

  Third-party scraping APIs are billed as a complete, no-compromise solution for web scraping,
  but they often have reliability problems. You're essentially paying someone else to run
  a headless browser for you, but they're subject to the same issues as the headless browsers
  themselves in terms of reliability. It doesn't feel great to pay the high prices of a
  scraping service only to get back a failure unrelated to the site you're scraping being down.

  Because of its reliability, flat monthly price, and low resource consumption,
  Browsey makes a better *first* choice for your scraping needs. Then you can fall back to
  expensive third-party APIs when you encounter a site that really needs a headless browser.
  """
  alias Jido.Browser.Vendor.BrowseyHttp.ConnectionException
  alias Jido.Browser.Vendor.BrowseyHttp.SslException
  alias Jido.Browser.Vendor.BrowseyHttp.TimeoutException
  alias Jido.Browser.Vendor.BrowseyHttp.TooLargeException
  alias Jido.Browser.Vendor.BrowseyHttp.TooManyRedirectsException
  alias Jido.Browser.Vendor.BrowseyHttp.Util
  alias Jido.Browser.Vendor.BrowseyHttp.Util.Curl
  alias Jido.Browser.Vendor.BrowseyHttp.Util.Html

  @max_response_size_mb 5
  @max_response_size_bytes @max_response_size_mb * 1024 * 1024

  @type uri_or_url :: URI.t() | String.t()
  @type get_result :: {:ok, Jido.Browser.Vendor.BrowseyHttp.Response.t()} | {:error, Exception.t()}

  @type browser :: :chrome | :chrome_android | :android | :edge | :safari

  @type http_get_option ::
          {:follow_redirects?, boolean()}
          | {:max_retries, non_neg_integer()}
          # | {:additional_headers, Jido.Browser.Vendor.BrowseyHttp.Response.headers()}
          | {:max_response_size_bytes, non_neg_integer() | :infinity}
          | {:receive_timeout, timeout()}
          | {:browser, browser() | :random}
          | {:ignore_ssl_errors?, boolean()}
          | {:timeout, timeout()}
          | {:cookie_file, Path.t()}

  @available_browsers %{
    chrome: "curl_chrome116",
    chrome_android: "curl_chrome99_android",
    edge: "curl_edge101",
    safari: "curl_safari15_5"
  }

  @browser_aliases %{android: :chrome_android}

  # Matches Chrome's behavior:
  # https://stackoverflow.com/questions/10895406/what-is-the-maximum-number-of-http-redirections-allowed-by-all-major-browsers
  @max_redirects 19

  @doc """
  Performs an HTTP GET request for a single resource, limiting the size we process to protect the server.

  Note that to fully imitate a browser, you may want to instead use
  `Jido.Browser.Vendor.BrowseyHttp.get_with_resources/2` to retrieve both the page itself and its
  embedded resources (CSS, JavaScript, images, etc.) at once.

  ### Options

  - `:max_response_size_bytes`: The maximum size of the response body, in bytes, or `:infinity`.
     If the response body exceeds this size, we'll return a `TooLargeException`. This is important
     so that unintentionally downloading, say, a huge video file doesn't run your server out
     of memory. Defaults to 5,242,880 (5 MiB).
  - `:follow_redirects?`: whether to follow redirects. Defaults to true, in which case the
     complete chain of redirects will be tracked in the `Jido.Browser.Vendor.BrowseyHttp.Response` struct's
     `:uri_sequence` field.
  - `:max_retries`: how many times to retry when the HTTP status code indicates an error.
     Defaults to 0.
  - `:receive_timeout`: The maximum time (in milliseconds) to wait to receive a response after
    connecting to the server. Defaults to 30,000 (30 seconds).
  - `:browser`: One of `:chrome`, `:chrome_android`, `:edge`, `:safari`, or `:random`.
    Defaults to `:chrome`, except for domains known to block our Chrome version,
    in which case a better default will be chosen.
  - `:ignore_ssl_errors?`: If true, we won't produce an `SslException` when the SSL handshake
    fails. This can be useful when the remote server has a root certificate that is unknown
    to the browser (including self-signed certificates). Use with caution, of course.
    Defaults to false.

  ### Examples

      iex> case Jido.Browser.Vendor.BrowseyHttp.get("https://www.example.com") do
      ...>   {:ok, %Jido.Browser.Vendor.BrowseyHttp.Response{body: body}} -> String.slice(body, 0, 15)
      ...>   {:error, exception} -> exception
      ...> end
      "<!doctype html>"
  """
  @spec get(uri_or_url(), [http_get_option()]) :: get_result()
  def get(url_or_uri, opts \\ []) do
    with {:ok, opts} <- validate_opts(opts),
         {:ok, %URI{} = uri} <- validate_url(url_or_uri) do
      start_time = DateTime.utc_now()
      retries = Access.get(opts, :max_retries, 0)

      Enum.reduce_while(0..retries, nil, fn attempt, _ ->
        result = get_internal(uri, [], opts)
        {error_or_ok, resp_or_exception} = result

        if should_retry?(resp_or_exception) and attempt < retries do
          Process.sleep(retry_delay_slow(attempt))
          {:cont, result}
        else
          {:halt, {error_or_ok, finalize_response(resp_or_exception, start_time)}}
        end
      end)
    end
  end

  @spec get!(uri_or_url(), [http_get_option()]) :: Jido.Browser.Vendor.BrowseyHttp.Response.t() | no_return
  def get!(url_or_uri, opts \\ []) do
    case get(url_or_uri, opts) do
      {:ok, resp} -> resp
      {:error, exception} -> raise exception
    end
  end

  @type resource_option ::
          {:ignore_uris, Enumerable.t(URI.t())}
          | {:fetch_images?, boolean()}
          | {:fetch_css?, boolean()}
          | {:fetch_js?, boolean()}
          | {:load_resources_when_redirected_off_host?, boolean()}

  @type resource_responses :: [Jido.Browser.Vendor.BrowseyHttp.Response.t() | Exception.t()]

  @doc """
  Performs an HTTP GET request for a resource plus any embedded resources (CSS, JavaScript, images, etc.).

  This matches how a real browser fetches a page by retrieving the resources in parallel.

  On success, the first of the returned response structs will always be the initial HTML page.

  If the initial HTML page fails to load, we'll return an error tuple. However, if any of the
  embedded resources fail to load entirely (that is, they don't merely return an HTTP error
  like a 404, but they would cause an `:error` return from `Jido.Browser.Vendor.BrowseyHttp.get/2`, such as a
  no-such-domain error or a timeout), they'll simply be left out of the returned response list.

  If the initial resource we retrieve is not HTML, on success we'll return an ok tuple
  with a single response struct.

  ### Options

  - Control the individual requests using the same options as `Jido.Browser.Vendor.BrowseyHttp.get/2`.
  - `:ignore_uris`: An enumerable of URI structs that we will skip fetching when they
    are referenced as resources. You can use this to do things like avoid re-crawling
    images that are present in the header of every page. Defaults to the empty set.
  - `:fetch_images?`: Whether to fetch images referenced in `<img>` and `<link rel="icon">` tags.
    Defaults to true.
  - `:fetch_css?`: Whether to fetch CSS files referenced in `<link rel="stylesheet">` tags.
    Defaults to true.
  - `:fetch_js?`: Whether to fetch JavaScript files referenced in `<script>` tags.
    Defaults to true.
  - `:load_resources_when_redirected_off_host?`: If false, we'll skip crawling resources if
    the URL redirects to a different host. Defaults to false to prevent unintentionally
    loading resources from a site you didn't expect.
  """
  @spec get_with_resources(uri_or_url(), [http_get_option() | resource_option()]) ::
          {:ok, [Jido.Browser.Vendor.BrowseyHttp.Response.t() | resource_responses()]} | {:error, Exception.t()}
  def get_with_resources(url_or_uri, opts \\ []) do
    case stream_with_resources(url_or_uri, opts) do
      {:ok, responses} -> {:ok, Enum.to_list(responses)}
      error -> error
    end
  end

  @doc """
  Same as `Jido.Browser.Vendor.BrowseyHttp.get_with_resources/2`, but when the primary result succeeds, returns a stream of responses.

  As with the non-streaming version, the first response will always be the initial resource.
  """
  @spec stream_with_resources(uri_or_url(), [http_get_option() | resource_option()]) ::
          {:ok, Enumerable.t(Jido.Browser.Vendor.BrowseyHttp.Response.t() | Exception.t())}
          | {:error, Exception.t()}
  def stream_with_resources(url_or_uri, opts \\ []) do
    case get(url_or_uri, opts) do
      {:ok, resp} ->
        if Jido.Browser.Vendor.BrowseyHttp.Response.html?(resp) and crawl_resources?(resp, opts) do
          {:ok, Stream.concat([resp], stream_embedded_resources(resp, opts))}
        else
          {:ok, [resp]}
        end

      error ->
        error
    end
  end

  @spec default_browser(uri_or_url()) :: browser()
  def default_browser(%URI{} = uri) do
    domain = Util.Uri.host_without_subdomains(uri)
    Map.get(browser_default_overrides_by_domain(), domain, :chrome)
  end

  def default_browser(url) when is_binary(url) do
    url
    |> URI.parse()
    |> default_browser()
  end

  defp browser_default_overrides_by_domain do
    %{"realtor.com" => :chrome_android}
  end

  @spec get_internal(URI.t(), [URI.t()], Keyword.t()) ::
          {:ok, Jido.Browser.Vendor.BrowseyHttp.Response.t()} | {:error, Exception.t()}
  defp get_internal(%URI{} = uri, prev_uris, opts) do
    default_browser_for_host = default_browser(uri)

    browser_script = browser_script(Access.get(opts, :browser, default_browser_for_host), default_browser_for_host)

    script = Application.app_dir(:jido_browser, ["priv", "vendor", "browsey_http", "curl", browser_script])

    # TODO: Support opts[:additional_headers]
    # Someday We could use the `:into` argument to stream and parse the request as it goes...

    timeout = Access.get(opts, :timeout, :timer.seconds(30))
    max_bytes = Access.get(opts, :max_response_size_bytes, @max_response_size_bytes)

    redirect_args =
      if Access.get(opts, :follow_redirects?, true) do
        ["--location", "--max-redirs", Integer.to_string(@max_redirects)]
      else
        []
      end

    security_args =
      if Access.get(opts, :ignore_ssl_errors?, false) do
        ["--insecure"]
      else
        []
      end

    {cookie_file, cleanup_cookie?} = request_cookie_file(opts)

    args =
      [
        script,
        "-v",
        to_string(uri)
      ] ++
        redirect_args ++
        security_args ++
        [
          "--max-time",
          Float.to_string(timeout / 1_000),
          "--cookie",
          cookie_file,
          "--cookie-jar",
          cookie_file
        ] ++ max_filesize_args(max_bytes) ++ server_side_rendering_header_args(uri)

    try do
      command = shell_join(args)

      with {:ok, result} <- Util.Exec.exec(command, timeout + 5_000),
           metadata = Enum.join(result[:stderr] || []),
           {:ok, %Curl.Result{} = metadata} <- Curl.parse_metadata(metadata, uri) do
        body = Enum.join(result[:stdout] || [])
        {:ok, curl_output_to_response(body, metadata, prev_uris)}
      else
        {:error, error_kwlist} ->
          metadata = Enum.join(error_kwlist[:stderr] || [])

          status =
            case Curl.parse_metadata(metadata, uri) do
              {:error, %Curl.Error{code: code}} -> code
              _ -> Access.fetch!(error_kwlist, :exit_status)
            end

          case status do
            3 -> {:error, ConnectionException.invalid_url(uri)}
            6 -> {:error, ConnectionException.could_not_resolve_host(uri)}
            7 -> {:error, ConnectionException.could_not_connect(uri)}
            28 -> {:error, TimeoutException.timed_out(uri, timeout)}
            35 -> {:error, SslException.new(uri)}
            47 -> {:error, TooManyRedirectsException.new(uri, @max_redirects)}
            56 -> {:error, ConnectionException.failed_to_receive(uri)}
            60 -> {:error, SslException.new(uri)}
            63 -> {:error, TooLargeException.new(uri, max_bytes)}
            _ -> {:error, ConnectionException.unknown_error(uri, status)}
          end
      end
    after
      if cleanup_cookie?, do: File.rm(cookie_file)
    end
  end

  defp request_server_side_rendering_user_agent do
    # Using GoogleBot on Twitter returns a 403; some other well-known bots apparently are expected
    # to execute the Javascript. Baidu apparently neither sends auth nor executes the page.
    baidu_bot =
      "Mozilla/5.0 (compatible; Baiduspider/2.0; +http://www.baidu.com/search/spider.html)"

    "User-Agent: #{baidu_bot}"
  end

  defp browser_script(:random, _default_browser) do
    @available_browsers |> Map.values() |> Enum.random()
  end

  defp browser_script(browser, default_browser) do
    browser =
      @browser_aliases
      |> Map.get(browser, browser)
      |> case do
        b when is_map_key(@available_browsers, b) -> b
        _ -> default_browser
      end

    Map.fetch!(@available_browsers, browser)
  end

  defp server_side_rendering_header_args(%URI{host: host}) when host in ["twitter.com", "x.com"] do
    ["--header", request_server_side_rendering_user_agent()]
  end

  defp server_side_rendering_header_args(_uri), do: []

  defp max_filesize_args(:infinity), do: []
  defp max_filesize_args(max_bytes), do: ["--max-filesize", Integer.to_string(max_bytes)]

  defp request_cookie_file(opts) do
    case Access.get(opts, :cookie_file) do
      path when is_binary(path) and path != "" ->
        {path, false}

      _ ->
        {Path.join(System.tmp_dir!(), "browsey_cookie_#{System.unique_integer([:positive])}"), true}
    end
  end

  defp validate_opts(opts) when is_list(opts) do
    if Keyword.keyword?(opts) do
      Enum.reduce_while(opts, {:ok, opts}, fn {key, value}, {:ok, acc} ->
        case validate_option(key, value) do
          :ok -> {:cont, {:ok, acc}}
          {:error, error} -> {:halt, {:error, error}}
        end
      end)
    else
      {:error, ArgumentError.exception("BrowseyHttp options must be a keyword list")}
    end
  end

  defp validate_opts(_opts), do: {:error, ArgumentError.exception("BrowseyHttp options must be a keyword list")}

  defp validate_option(key, value) when key in [:follow_redirects?, :ignore_ssl_errors?] and is_boolean(value), do: :ok

  defp validate_option(:max_retries, value) do
    if is_integer(value) and value >= 0 do
      :ok
    else
      {:error, ArgumentError.exception("max_retries must be a non-negative integer")}
    end
  end

  defp validate_option(key, value) when key in [:timeout, :receive_timeout] do
    if is_integer(value) and value > 0 do
      :ok
    else
      {:error, ArgumentError.exception("#{key} must be a positive integer")}
    end
  end

  defp validate_option(:max_response_size_bytes, :infinity), do: :ok

  defp validate_option(:max_response_size_bytes, value) do
    if is_integer(value) and value >= 0 do
      :ok
    else
      {:error, ArgumentError.exception("max_response_size_bytes must be a non-negative integer or :infinity")}
    end
  end

  defp validate_option(:browser, browser) do
    browser = Map.get(@browser_aliases, browser, browser)

    if browser == :random or Map.has_key?(@available_browsers, browser) do
      :ok
    else
      {:error, ArgumentError.exception("browser must be one of :chrome, :chrome_android, :edge, :safari, or :random")}
    end
  end

  defp validate_option(:cookie_file, value) when is_binary(value) and value != "", do: :ok

  defp validate_option(:cookie_file, _value) do
    {:error, ArgumentError.exception("cookie_file must be a non-empty path")}
  end

  defp validate_option(key, _value) do
    {:error, ArgumentError.exception("unsupported BrowseyHttp option #{inspect(key)}")}
  end

  defp shell_join(args) do
    args
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.map(&shell_quote/1)
    |> Enum.join(" ")
  end

  defp shell_quote(value) do
    "'" <> String.replace(to_string(value), "'", "'\\''") <> "'"
  end

  defp curl_output_to_response(curl_output, %Curl.Result{} = metadata, prev_uris) do
    %{headers: headers, uris: uris, status: status} = metadata

    %Jido.Browser.Vendor.BrowseyHttp.Response{
      body: curl_output,
      headers: headers,
      status: status,
      final_uri: List.last(uris),
      uri_sequence: prev_uris ++ uris,
      runtime_ms: 0
    }
  end

  defp finalize_response(%Jido.Browser.Vendor.BrowseyHttp.Response{} = resp, start_time) do
    runtime_ms = DateTime.diff(DateTime.utc_now(), start_time, :millisecond)
    %{resp | runtime_ms: runtime_ms}
  end

  defp finalize_response(error, _), do: error

  defp should_retry?(%Jido.Browser.Vendor.BrowseyHttp.Response{status: status}) do
    status >= 400
  end

  defp should_retry?(%TimeoutException{}), do: true
  defp should_retry?(%ConnectionException{}), do: true

  defp should_retry?(%SslException{}), do: false
  defp should_retry?(%TooLargeException{}), do: false
  defp should_retry?(%TooManyRedirectsException{}), do: false

  @spec stream_embedded_resources(
          Jido.Browser.Vendor.BrowseyHttp.Response.t(),
          [http_get_option() | resource_option()]
        ) ::
          Enumerable.t(Jido.Browser.Vendor.BrowseyHttp.Response.t() | Exception.t())
  defp stream_embedded_resources(%Jido.Browser.Vendor.BrowseyHttp.Response{final_uri: uri} = resp, opts) do
    case Floki.parse_document(resp.body) do
      {:ok, parsed} ->
        ignore_uris = MapSet.new(opts[:ignore_uris] || [])
        fetch = Access.get(opts, :get, &get(&1, opts))

        # A browser would load these resources inline, without any throttling, so it's
        # safe for us to do so as well.
        uris_to_fetch =
          parsed
          |> Html.urls_a_browser_would_load_immediately(opts)
          |> MapSet.new(&Util.Uri.canonical_uri(&1, uri))
          |> MapSet.difference(ignore_uris)

        uris_to_fetch
        |> Task.async_stream(fetch,
          max_concurrency: min(4, System.schedulers_online()),
          ordered: false,
          timeout: MapSet.size(uris_to_fetch) * :timer.minutes(1),
          on_timeout: :kill_task
        )
        |> Stream.filter(&match?({:ok, _}, &1))
        |> Stream.map(fn {:ok, result} -> result end)
        |> Stream.map(fn
          {:ok, result} -> result
          {:error, exception} -> exception
        end)

      _ ->
        []
    end
  end

  @spec crawl_resources?(Jido.Browser.Vendor.BrowseyHttp.Response.t(), [resource_option()]) ::
          boolean()
  defp crawl_resources?(%Jido.Browser.Vendor.BrowseyHttp.Response{} = resp, opts) do
    %Jido.Browser.Vendor.BrowseyHttp.Response{final_uri: %URI{} = final, uri_sequence: [%URI{} = first | _]} = resp
    opts[:load_resources_when_redirected_off_host?] || final.host == first.host
  end

  defp validate_url(url) when is_binary(url) do
    url
    |> URI.parse()
    |> validate_url()
  end

  defp validate_url(%URI{} = uri) do
    case uri do
      %URI{scheme: scheme, host: host} when byte_size(host) > 0 and scheme in ["http", "https"] ->
        {:ok, uri}

      _ ->
        {:error, ConnectionException.invalid_url(uri)}
    end
  end

  # TODO: Make this configurable
  if Mix.env() == :test do
    defp retry_delay_slow(retry_count), do: 1 + retry_count
  else
    # Exponential backoff starting at 4 seconds, then 8, 16, etc.
    defp retry_delay_slow(retry_count), do: :timer.seconds(2 ** (3 + retry_count))
  end
end
