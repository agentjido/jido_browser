defmodule Jido.Browser.WebFetch do
  @moduledoc """
  Stateless HTTP-first web retrieval with optional domain policy, caching,
  focused filtering, citation-ready passage metadata, and Extractous-backed
  document extraction.

  This module is intended for document retrieval workloads where starting a full
  browser session would be unnecessary or too expensive.
  """

  alias Jido.Browser.Error

  import Bitwise, only: [bsl: 2, bsr: 2]

  @cache_table :jido_browser_web_fetch_cache
  @default_backend Jido.Browser.WebFetch.Backends.Req
  @default_timeout 15_000
  @default_req_max_redirects 10
  @default_browsey_max_redirects 19
  @default_cache_ttl_ms 300_000
  @default_max_url_length 2_048
  @policy_error_code :url_not_allowed
  @redirect_statuses [301, 302, 303, 307, 308]
  @cross_origin_req_options [
    :auth,
    :aws_sigv4,
    :base_url,
    :params,
    :path_params,
    :path_params_style
  ]
  @post_redirect_body_options [:body, :json, :form, :form_multipart]
  @body_headers ["content-length", "content-type"]
  @cross_origin_headers ["authorization", "proxy-authorization", "cookie", "cookie2"]
  @supported_formats [:markdown, :text, :html]
  # IANA IPv4 Special-Purpose Address Space plus the IPv4 multicast block.
  # https://www.iana.org/assignments/iana-ipv4-special-registry/
  @ipv4_special_ranges [
    {{0, 0, 0, 0}, 8, :this_network},
    {{10, 0, 0, 0}, 8, :private},
    {{100, 64, 0, 0}, 10, :shared_address_space},
    {{127, 0, 0, 0}, 8, :loopback},
    {{169, 254, 0, 0}, 16, :link_local},
    {{172, 16, 0, 0}, 12, :private},
    {{192, 0, 0, 0}, 24, :special_use},
    {{192, 0, 2, 0}, 24, :documentation},
    {{192, 31, 196, 0}, 24, :special_use},
    {{192, 52, 193, 0}, 24, :special_use},
    {{192, 88, 99, 0}, 24, :special_use},
    {{192, 168, 0, 0}, 16, :private},
    {{192, 175, 48, 0}, 24, :special_use},
    {{198, 18, 0, 0}, 15, :benchmarking},
    {{198, 51, 100, 0}, 24, :documentation},
    {{203, 0, 113, 0}, 24, :documentation},
    {{224, 0, 0, 0}, 4, :multicast},
    {{240, 0, 0, 0}, 4, :reserved}
  ]
  # IANA IPv6 Special-Purpose Address Space. All other allowed IPv6 addresses
  # must also be in the global-unicast 2000::/3 block.
  # https://www.iana.org/assignments/iana-ipv6-special-registry/
  @ipv6_special_ranges [
    {{0, 0, 0, 0, 0, 0, 0, 0}, 128, :unspecified},
    {{0, 0, 0, 0, 0, 0, 0, 1}, 128, :loopback},
    {{0, 0, 0, 0, 0, 0xFFFF, 0, 0}, 96, :ipv4_mapped},
    {{0x0064, 0xFF9B, 0, 0, 0, 0, 0, 0}, 96, :translation},
    {{0x0064, 0xFF9B, 1, 0, 0, 0, 0, 0}, 48, :translation},
    {{0x0100, 0, 0, 0, 0, 0, 0, 0}, 64, :discard_only},
    {{0x0100, 0, 0, 1, 0, 0, 0, 0}, 64, :special_use},
    {{0x2001, 0, 0, 0, 0, 0, 0, 0}, 23, :special_use},
    {{0x2001, 0x0DB8, 0, 0, 0, 0, 0, 0}, 32, :documentation},
    {{0x2002, 0, 0, 0, 0, 0, 0, 0}, 16, :special_use},
    {{0x2620, 0x004F, 0x8000, 0, 0, 0, 0, 0}, 48, :special_use},
    {{0x3FFF, 0, 0, 0, 0, 0, 0, 0}, 20, :documentation},
    {{0x5F00, 0, 0, 0, 0, 0, 0, 0}, 16, :special_use},
    {{0xFC00, 0, 0, 0, 0, 0, 0, 0}, 7, :private},
    {{0xFE80, 0, 0, 0, 0, 0, 0, 0}, 10, :link_local},
    {{0xFF00, 0, 0, 0, 0, 0, 0, 0}, 8, :multicast}
  ]
  @ipv6_global_unicast {{0x2000, 0, 0, 0, 0, 0, 0, 0}, 3}
  @html_content_types ["text/html", "application/xhtml+xml"]
  @text_content_types [
    "text/plain",
    "text/markdown",
    "text/csv",
    "text/xml",
    "application/xml",
    "application/json",
    "application/ld+json"
  ]
  @document_content_types %{
    "application/pdf" => :pdf,
    "application/msword" => :word_processing,
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document" => :word_processing,
    "application/vnd.ms-word.document.macroenabled.12" => :word_processing,
    "application/vnd.openxmlformats-officedocument.wordprocessingml.template" => :word_processing,
    "application/vnd.ms-word.template.macroenabled.12" => :word_processing,
    "application/vnd.ms-excel" => :spreadsheet,
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" => :spreadsheet,
    "application/vnd.ms-excel.sheet.macroenabled.12" => :spreadsheet,
    "application/vnd.openxmlformats-officedocument.spreadsheetml.template" => :spreadsheet,
    "application/vnd.ms-excel.template.macroenabled.12" => :spreadsheet,
    "application/vnd.ms-powerpoint" => :presentation,
    "application/vnd.openxmlformats-officedocument.presentationml.presentation" => :presentation,
    "application/vnd.ms-powerpoint.presentation.macroenabled.12" => :presentation,
    "application/vnd.openxmlformats-officedocument.presentationml.slideshow" => :presentation,
    "application/vnd.openxmlformats-officedocument.presentationml.template" => :presentation,
    "application/vnd.oasis.opendocument.text" => :word_processing,
    "application/vnd.oasis.opendocument.spreadsheet" => :spreadsheet,
    "application/vnd.oasis.opendocument.presentation" => :presentation,
    "application/rtf" => :word_processing,
    "text/rtf" => :word_processing,
    "application/epub+zip" => :ebook,
    "message/rfc822" => :email,
    "application/vnd.ms-outlook" => :email
  }
  @document_extensions %{
    "pdf" => :pdf,
    "doc" => :word_processing,
    "docx" => :word_processing,
    "docm" => :word_processing,
    "dotx" => :word_processing,
    "dotm" => :word_processing,
    "odt" => :word_processing,
    "rtf" => :word_processing,
    "xls" => :spreadsheet,
    "xlsx" => :spreadsheet,
    "xlsm" => :spreadsheet,
    "xlsb" => :spreadsheet,
    "ods" => :spreadsheet,
    "ppt" => :presentation,
    "pptx" => :presentation,
    "pptm" => :presentation,
    "ppsx" => :presentation,
    "odp" => :presentation,
    "epub" => :ebook,
    "eml" => :email,
    "msg" => :email
  }

  @type result :: %{
          required(:url) => String.t(),
          required(:final_url) => String.t(),
          required(:content) => String.t(),
          required(:format) => atom(),
          required(:content_type) => String.t(),
          required(:document_type) => atom(),
          required(:retrieved_at) => String.t(),
          required(:estimated_tokens) => non_neg_integer(),
          required(:original_estimated_tokens) => non_neg_integer(),
          required(:truncated) => boolean(),
          required(:filtered) => boolean(),
          required(:focus_matches) => non_neg_integer(),
          required(:cached) => boolean(),
          required(:citations) => %{enabled: boolean()},
          required(:passages) => list(map()),
          optional(:title) => String.t() | nil,
          optional(:metadata) => map()
        }

  @doc """
  Fetches a URL over HTTP(S) and returns normalized document content.

  Supported options:
  - `:format` - `:markdown`, `:text`, or `:html`
  - `:selector` - CSS selector for HTML pages
  - `:allowed_domains` / `:blocked_domains` - mutually exclusive host/path rules
  - `:allow_private_network` - allow private network destinations, defaults to `false`
  - `:max_content_tokens` - approximate token cap
  - `:citations` - boolean, when true include passage spans
  - `:focus_terms` - list of terms used for focused filtering
  - `:focus_window` - paragraph window around focus matches
  - `:timeout` - receive timeout in milliseconds
  - `:max_redirects` - redirect limit; overrides a nested Req limit
  - `:cache` - enable ETS cache, defaults to `true`
  - `:cache_ttl_ms` - cache TTL in milliseconds
  - `:require_known_url` / `:known_urls` - optional URL provenance guard
  - `:extractous` - optional `ExtractousEx` keyword options merged with config
  """
  @spec fetch(String.t(), keyword()) :: {:ok, result()} | {:error, Exception.t()}
  def fetch(url, opts \\ [])

  def fetch(url, opts) when is_binary(url) and is_list(opts) do
    with {:ok, opts} <- normalize_opts(opts),
         {:ok, normalized_url, uri} <- validate_url(url, opts),
         :ok <- validate_known_url(normalized_url, opts),
         :ok <- validate_domain_filters(uri, opts) do
      case fetch_cached(normalized_url, opts) do
        {:ok, result} ->
          {:ok, result}

        :miss ->
          do_fetch(normalized_url, opts)
      end
    end
  end

  def fetch(url, _opts) do
    {:error, Error.invalid_error("URL must be a non-empty string", %{error_code: :invalid_input, url: url})}
  end

  @doc false
  @spec clear_cache() :: :ok
  def clear_cache do
    case :ets.whereis(@cache_table) do
      :undefined ->
        :ok

      table ->
        :ets.delete_all_objects(table)
        :ok
    end
  end

  defp do_fetch(url, opts) do
    with {:ok, request_opts, cookie_file} <- prepare_redirect_chain(opts) do
      try do
        with {:ok, response, final_url, _final_uri} <- fetch_with_redirects(url, request_opts),
             :ok <- validate_http_status(response, url),
             {:ok, result} <- build_result(url, final_url, response, request_opts) do
          maybe_store_cache(url, request_opts, result)
          {:ok, result}
        end
      after
        if cookie_file, do: File.rm(cookie_file)
      end
    end
  end

  defp prepare_redirect_chain(opts) do
    browsey_backend = Jido.Browser.WebFetch.Backends.Browsey
    browsey_opts = opts[:browsey] || []

    if opts[:backend] == browsey_backend and not Keyword.has_key?(browsey_opts, :cookie_file) do
      cookie_file =
        Path.join(
          System.tmp_dir!(),
          "jido_browser_cookie_#{Base.url_encode64(:crypto.strong_rand_bytes(18), padding: false)}"
        )

      case File.open(cookie_file, [:write, :exclusive]) do
        {:ok, file} ->
          File.close(file)
          File.chmod(cookie_file, 0o600)

          request_opts =
            opts
            |> Keyword.put(:browsey, Keyword.put(browsey_opts, :cookie_file, cookie_file))
            |> Keyword.put(:managed_browsey_cookie_file, cookie_file)

          {:ok, request_opts, cookie_file}

        {:error, reason} ->
          {:error,
           Error.adapter_error("Web fetch could not create a redirect cookie file", %{
             error_code: :unavailable,
             reason: reason
           })}
      end
    else
      {:ok, opts, nil}
    end
  end

  defp fetch_with_redirects(url, opts) do
    with {:ok, current_url, request_opts} <- prepare_initial_request_url(url, opts) do
      fetch_with_redirects(current_url, request_opts, 0)
    end
  end

  defp prepare_initial_request_url(url, opts) do
    req_backend = Jido.Browser.WebFetch.Backends.Req
    req_opts = opts[:req] || []
    transform_keys = [:params, :path_params, :path_params_style]

    if opts[:backend] == req_backend and Enum.any?(transform_keys, &Keyword.has_key?(req_opts, &1)) do
      transform_opts = Keyword.take(req_opts, transform_keys)

      request =
        [url: url]
        |> Keyword.merge(transform_opts)
        |> Req.new()
        |> Req.Steps.put_params()
        |> Req.Steps.put_path_params()

      transformed_url = URI.to_string(request.url)
      request_opts = Keyword.put(opts, :req, Keyword.drop(req_opts, transform_keys))

      case validate_url(transformed_url, request_opts) do
        {:ok, normalized_url, _uri} -> {:ok, normalized_url, request_opts}
        {:error, _reason} = error -> error
      end
    else
      {:ok, url |> URI.parse() |> normalize_uri() |> URI.to_string(), opts}
    end
  rescue
    _error ->
      {:error,
       Error.invalid_error("Req URL parameters are invalid", %{
         error_code: :invalid_input
       })}
  end

  defp fetch_with_redirects(current_url, opts, redirect_count) do
    backend = opts[:backend]

    with {:ok, request_opts} <- prepare_destination(current_url, opts),
         {:ok, response} <- fetch_prepared_destination(backend, current_url, request_opts),
         {:ok, response} <- ensure_backend_kept_request_url(response, current_url) do
      follow_redirect(response, current_url, opts, redirect_count)
    end
  end

  defp ensure_backend_kept_request_url(response, current_url) do
    expected_url = current_url |> URI.parse() |> normalize_uri() |> URI.to_string()

    case normalize_final_url(response) do
      {:ok, ^expected_url, _uri} ->
        {:ok, Map.put(response, :final_url, expected_url)}

      {:ok, backend_url, _uri} ->
        destination_policy_error("Web fetch backend followed an unvalidated redirect", %{
          requested_url: expected_url,
          backend_url: backend_url
        })

      {:error, _reason} = error ->
        error
    end
  end

  defp follow_redirect(response, current_url, opts, redirect_count) do
    if response.status in @redirect_statuses do
      case redirect_location(response) do
        {:ok, location} -> follow_redirect_location(response, current_url, location, opts, redirect_count)
        {:error, reason} -> invalid_redirect_error(current_url, reason)
      end
    else
      finish_redirects(response, current_url)
    end
  end

  defp follow_redirect_location(response, current_url, location, opts, redirect_count) do
    if redirect_count >= opts[:max_redirects] do
      {:error,
       Error.adapter_error("Web fetch exceeded redirect limit", %{
         error_code: :url_not_accessible,
         max_redirects: opts[:max_redirects],
         url: current_url
       })}
    else
      with {:ok, redirect_url, redirect_uri} <- resolve_redirect_url(current_url, location, opts),
           :ok <- validate_domain_filters(redirect_uri, opts),
           {:ok, redirect_opts} <-
             redirect_request_opts(opts, current_url, redirect_uri, response.status) do
        fetch_with_redirects(redirect_url, redirect_opts, redirect_count + 1)
      end
    end
  end

  defp resolve_redirect_url(current_url, location, opts) do
    case build_strict_redirect_url(current_url, location, opts) do
      {:ok, _redirect_url, _redirect_uri} = result ->
        result

      {:error, reason} ->
        invalid_redirect_error(current_url, {:rejected_location, location, reason})
    end
  rescue
    error ->
      invalid_redirect_error(current_url, {:invalid_location, location, error})
  end

  defp build_strict_redirect_url(current_url, location, opts) do
    with :ok <- validate_redirect_text(location),
         {:ok, reference} <- URI.new(location),
         :ok <- validate_redirect_reference(reference, location),
         merged_uri = URI.merge(URI.parse(current_url), reference),
         :ok <- validate_redirect_target_uri(merged_uri),
         normalized_uri = normalize_uri(merged_uri),
         redirect_url = URI.to_string(normalized_uri),
         :ok <- validate_redirect_url_length(redirect_url, opts) do
      {:ok, redirect_url, normalized_uri}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_redirect_text(location) do
    cond do
      location == "" -> {:error, :missing_location}
      forbidden_redirect_byte?(location) -> {:error, :forbidden_character}
      not valid_percent_escapes?(location) -> {:error, :invalid_percent_escape}
      true -> :ok
    end
  end

  defp forbidden_redirect_byte?(location) do
    location
    |> :binary.bin_to_list()
    |> Enum.any?(fn byte -> byte <= 0x20 or byte == 0x7F or byte == ?\\ end)
  end

  defp valid_percent_escapes?(<<>>), do: true

  defp valid_percent_escapes?(<<?%, high, low, rest::binary>>) do
    case {hex_value(high), hex_value(low)} do
      {{:ok, high_value}, {:ok, low_value}} ->
        decoded = high_value * 16 + low_value
        decoded > 0x1F and decoded != 0x7F and valid_percent_escapes?(rest)

      _other ->
        false
    end
  end

  defp valid_percent_escapes?(<<?%, _rest::binary>>), do: false
  defp valid_percent_escapes?(<<_byte, rest::binary>>), do: valid_percent_escapes?(rest)

  defp hex_value(value) when value in ?0..?9, do: {:ok, value - ?0}
  defp hex_value(value) when value in ?A..?F, do: {:ok, value - ?A + 10}
  defp hex_value(value) when value in ?a..?f, do: {:ok, value - ?a + 10}
  defp hex_value(_value), do: :error

  defp validate_redirect_reference(%URI{} = uri, location) do
    with :ok <- validate_redirect_scheme(uri.scheme, allow_relative?: true),
         :ok <- validate_redirect_userinfo(uri.userinfo),
         :ok <- validate_redirect_authority(uri, location),
         :ok <- validate_optional_redirect_host(uri.host),
         :ok <- validate_redirect_port(uri.port) do
      validate_redirect_path(uri.host, uri.path)
    end
  end

  defp validate_redirect_target_uri(%URI{} = uri) do
    with :ok <- validate_redirect_scheme(uri.scheme, allow_relative?: false),
         :ok <- validate_redirect_userinfo(uri.userinfo),
         :ok <- validate_required_redirect_host(uri.host),
         :ok <- validate_redirect_port(uri.port) do
      validate_redirect_path(uri.host, uri.path)
    end
  end

  defp validate_redirect_scheme(nil, allow_relative?: true), do: :ok

  defp validate_redirect_scheme(scheme, allow_relative?: _allow_relative) do
    if String.downcase(scheme || "") in ["http", "https"], do: :ok, else: {:error, :unsupported_scheme}
  end

  defp validate_redirect_userinfo(nil), do: :ok
  defp validate_redirect_userinfo(_userinfo), do: {:error, :userinfo_not_allowed}

  defp validate_redirect_authority(%URI{scheme: scheme, host: host}, location) do
    if (String.starts_with?(location, "//") or not is_nil(scheme)) and host in [nil, ""],
      do: {:error, :missing_host},
      else: :ok
  end

  defp validate_optional_redirect_host(nil), do: :ok
  defp validate_optional_redirect_host(host), do: validate_required_redirect_host(host)

  defp validate_required_redirect_host(host) when host in [nil, ""], do: {:error, :missing_host}

  defp validate_required_redirect_host(host) do
    if valid_redirect_host?(host), do: :ok, else: {:error, :invalid_host}
  end

  defp validate_redirect_port(nil), do: :ok
  defp validate_redirect_port(port) when port in 1..65_535, do: :ok
  defp validate_redirect_port(_port), do: {:error, :invalid_port}

  defp validate_redirect_path(nil, _path), do: :ok
  defp validate_redirect_path(_host, nil), do: :ok

  defp validate_redirect_path(_host, path) do
    if String.starts_with?(path, "/"), do: :ok, else: {:error, :invalid_path}
  end

  defp valid_redirect_host?(host) do
    case :inet.parse_address(String.to_charlist(host)) do
      {:ok, _address} -> true
      {:error, :einval} -> valid_dns_hostname?(host)
    end
  end

  defp valid_dns_hostname?(host) do
    trimmed_host = String.trim_trailing(host, ".")
    labels = String.split(trimmed_host, ".", trim: false)

    byte_size(host) <= 253 and ascii_only?(host) and trimmed_host != "" and
      Enum.all?(labels, fn label ->
        byte_size(label) in 1..63 and
          String.match?(label, ~r/\A[a-zA-Z0-9](?:[a-zA-Z0-9-]*[a-zA-Z0-9])?\z/)
      end)
  end

  defp validate_redirect_url_length(url, opts) do
    if String.length(url) <= (opts[:max_url_length] || @default_max_url_length),
      do: :ok,
      else: {:error, :url_too_long}
  end

  defp redirect_location(response) do
    response.headers
    |> response_header("location")
    |> List.first()
    |> case do
      location when is_binary(location) ->
        if location == "", do: {:error, :missing_location}, else: {:ok, location}

      nil ->
        {:error, :missing_location}

      value ->
        {:error, {:invalid_location, value}}
    end
  end

  defp invalid_redirect_error(current_url, reason) do
    destination_policy_error("Web fetch redirect location is not allowed", %{
      url: current_url,
      reason: reason
    })
  end

  defp redirect_request_opts(opts, current_url, redirect_uri, status) do
    current_uri = URI.parse(current_url)
    status_opts = apply_redirect_status(opts, status)

    if same_origin?(current_uri, redirect_uri) do
      {:ok, status_opts}
    else
      status_opts
      |> Keyword.update(:req, [], &remove_req_credentials/1)
      |> isolate_browsey_redirect_cookies(current_url)
    end
  end

  defp apply_redirect_status(opts, status) when status in [301, 302, 303] do
    req_backend = Jido.Browser.WebFetch.Backends.Req

    if opts[:backend] == req_backend do
      Keyword.update(opts, :req, [], &change_post_to_get/1)
    else
      opts
    end
  end

  defp apply_redirect_status(opts, _status), do: opts

  defp change_post_to_get(req_opts) do
    if Keyword.get(req_opts, :method, :get) == :post do
      req_opts
      |> Keyword.put(:method, :get)
      |> Keyword.drop(@post_redirect_body_options)
      |> Keyword.update(:headers, [], &remove_body_headers/1)
    else
      req_opts
    end
  end

  defp remove_body_headers(headers) when is_list(headers) or is_map(headers) do
    Enum.reject(headers, fn {name, _value} ->
      name |> to_string() |> String.downcase() |> then(&(&1 in @body_headers))
    end)
  end

  defp remove_body_headers(headers), do: headers

  defp same_origin?(left, right) do
    origin(left) == origin(right)
  end

  defp origin(%URI{} = uri) do
    {uri.scheme, String.downcase(uri.host || ""), uri.port || URI.default_port(uri.scheme)}
  end

  defp remove_req_credentials(req_opts) do
    req_opts
    |> Keyword.drop(@cross_origin_req_options)
    |> Keyword.update(:headers, [], &remove_origin_bound_headers/1)
    |> Keyword.update(:connect_options, [], &remove_proxy_credentials/1)
  end

  defp remove_origin_bound_headers(headers) when is_list(headers) or is_map(headers) do
    Enum.reject(headers, fn {name, _value} ->
      normalized_name = name |> to_string() |> String.downcase()
      normalized_name in @cross_origin_headers or String.starts_with?(normalized_name, "x-amz-")
    end)
  end

  defp remove_origin_bound_headers(headers), do: headers

  defp remove_proxy_credentials(connect_options) when is_list(connect_options) do
    Keyword.delete(connect_options, :proxy_headers)
  end

  defp remove_proxy_credentials(connect_options), do: connect_options

  defp isolate_browsey_redirect_cookies(opts, current_url) do
    browsey_backend = Jido.Browser.WebFetch.Backends.Browsey

    cond do
      opts[:backend] != browsey_backend ->
        {:ok, opts}

      cookie_file = opts[:managed_browsey_cookie_file] ->
        case File.write(cookie_file, "") do
          :ok -> {:ok, opts}
          {:error, reason} -> invalid_redirect_error(current_url, {:cookie_isolation_failed, reason})
        end

      true ->
        browsey_opts = Keyword.put(opts[:browsey] || [], :send_cookies?, false)
        {:ok, Keyword.put(opts, :browsey, browsey_opts)}
    end
  end

  defp finish_redirects(response, final_url) do
    final_uri = final_url |> URI.parse() |> normalize_uri()
    final_url = URI.to_string(final_uri)
    {:ok, Map.put(response, :final_url, final_url), final_url, final_uri}
  end

  defp build_result(url, final_url, response, opts) do
    content_type = response_content_type(response)
    document_type = extractable_document_type(content_type, final_url, response.body)

    cond do
      content_type in @html_content_types ->
        build_html_result(url, final_url, response.body, content_type, opts)

      not is_nil(document_type) ->
        build_document_result(url, final_url, response.body, content_type, document_type, opts)

      text_content_type?(content_type) ->
        build_text_result(url, final_url, response.body, content_type, opts)

      true ->
        {:error,
         Error.adapter_error("Unsupported content type for web fetch", %{
           error_code: :unsupported_content_type,
           content_type: content_type
         })}
    end
  end

  defp build_html_result(url, final_url, body, content_type, opts) when is_binary(body) do
    selector = opts[:selector]

    with {:ok, document} <- parse_document(body),
         {:ok, html} <- select_html(document, body, selector),
         {:ok, title} <- extract_title(document),
         {:ok, content} <- format_html(html, opts[:format], opts) do
      finalize_result(url, final_url, content, title, content_type, :html, opts)
    end
  end

  defp build_html_result(_url, _final_url, body, content_type, _opts) do
    {:error,
     Error.adapter_error("Unexpected response body for HTML fetch", %{
       error_code: :unavailable,
       content_type: content_type,
       body: body
     })}
  end

  defp build_text_result(url, final_url, body, content_type, opts) when is_binary(body) do
    with :ok <- validate_non_html_options(content_type, opts),
         {:ok, content} <- format_text(body, opts[:format]) do
      finalize_result(url, final_url, content, nil, content_type, :text, opts)
    end
  end

  defp build_text_result(_url, _final_url, body, content_type, _opts) do
    {:error,
     Error.adapter_error("Unexpected response body for text fetch", %{
       error_code: :unavailable,
       content_type: content_type,
       body: body
     })}
  end

  defp build_document_result(url, final_url, body, content_type, document_type, opts) when is_binary(body) do
    with :ok <- validate_non_html_options(content_type, opts),
         {:ok, text, metadata} <- extract_document_content(body, final_url, content_type, document_type, opts) do
      finalize_result(
        url,
        final_url,
        text,
        document_title(metadata, final_url),
        content_type,
        document_type,
        opts,
        metadata
      )
    end
  end

  defp build_document_result(_url, _final_url, body, content_type, _document_type, _opts) do
    {:error,
     Error.adapter_error("Unexpected response body for document fetch", %{
       error_code: :unavailable,
       content_type: content_type,
       body: body
     })}
  end

  defp build_response(opts, attrs) do
    passages = maybe_build_passages(attrs.content, attrs.title, attrs.final_url, opts[:citations])

    %{
      url: attrs.url,
      final_url: attrs.final_url,
      title: attrs.title,
      content: attrs.content,
      format: opts[:format],
      content_type: attrs.content_type,
      document_type: attrs.document_type,
      retrieved_at: retrieved_at(),
      estimated_tokens: estimate_tokens(attrs.content),
      original_estimated_tokens: attrs.original_estimated_tokens,
      truncated: attrs.truncated,
      filtered: attrs.filtered,
      focus_matches: attrs.focus_matches,
      cached: false,
      citations: %{enabled: opts[:citations]},
      passages: passages
    }
    |> maybe_put_metadata(attrs.metadata)
  end

  defp finalize_result(url, final_url, content, title, content_type, document_type, opts, metadata \\ nil) do
    with {:ok, filtered_content, filtered, focus_matches} <- maybe_filter_content(content, opts),
         {final_content, truncated, original_estimated_tokens} <-
           maybe_truncate(filtered_content, opts[:max_content_tokens]) do
      attrs = %{
        url: url,
        final_url: final_url,
        content: final_content,
        title: title,
        content_type: content_type,
        document_type: document_type,
        truncated: truncated,
        filtered: filtered,
        focus_matches: focus_matches,
        original_estimated_tokens: original_estimated_tokens,
        metadata: metadata
      }

      {:ok, build_response(opts, attrs)}
    end
  end

  defp validate_non_html_options(content_type, opts) do
    cond do
      opts[:selector] ->
        {:error,
         Error.invalid_error("Selector filtering is only supported for HTML content", %{
           error_code: :invalid_input,
           selector: opts[:selector],
           content_type: content_type
         })}

      opts[:format] == :html ->
        {:error,
         Error.invalid_error("HTML output is only supported for HTML content", %{
           error_code: :invalid_input,
           format: :html,
           content_type: content_type
         })}

      true ->
        :ok
    end
  end

  defp normalize_opts(opts) do
    format = opts[:format] || :markdown
    citations = normalize_citations(opts[:citations])
    focus_terms = normalize_focus_terms(opts[:focus_terms])

    with {:ok, backend} <- normalize_backend(Keyword.get(opts, :backend, config(:backend, @default_backend))),
         {:ok, configured_req_opts} <- normalize_backend_opts(:req, config(:req, [])),
         {:ok, request_req_opts} <- normalize_backend_opts(:req, Keyword.get(opts, :req, [])),
         {:ok, configured_browsey_opts} <- normalize_backend_opts(:browsey, config(:browsey, [])),
         {:ok, request_browsey_opts} <- normalize_backend_opts(:browsey, Keyword.get(opts, :browsey, [])),
         {:ok, configured_extractous_opts} <- normalize_extractous_opts(config(:extractous, [])),
         {:ok, request_extractous_opts} <- normalize_extractous_opts(Keyword.get(opts, :extractous, [])),
         {:ok, selector} <- normalize_selector(opts[:selector]),
         {:ok, focus_window} <- normalize_integer_opt(:focus_window, Keyword.get(opts, :focus_window, 0), min: 0),
         {:ok, timeout} <-
           normalize_integer_opt(:timeout, Keyword.get(opts, :timeout, config(:timeout, @default_timeout)), min: 1),
         {:ok, max_redirects} <-
           normalize_max_redirects(opts, backend, configured_req_opts, request_req_opts),
         {:ok, cache_ttl_ms} <-
           normalize_integer_opt(
             :cache_ttl_ms,
             Keyword.get(opts, :cache_ttl_ms, config(:cache_ttl_ms, @default_cache_ttl_ms)),
             min: 0
           ),
         {:ok, max_content_tokens} <-
           normalize_optional_integer_opt(:max_content_tokens, opts[:max_content_tokens], min: 1),
         {:ok, max_url_length} <- normalize_optional_integer_opt(:max_url_length, opts[:max_url_length], min: 1),
         {:ok, cache} <- normalize_boolean_opt(:cache, Keyword.get(opts, :cache, true)),
         {:ok, allow_private_network} <-
           normalize_boolean_opt(
             :allow_private_network,
             Keyword.get(opts, :allow_private_network, config(:allow_private_network, false))
           ),
         {:ok, require_known_url} <-
           normalize_boolean_opt(:require_known_url, Keyword.get(opts, :require_known_url, false)) do
      cond do
        format not in @supported_formats ->
          {:error,
           Error.invalid_error("Unsupported web fetch format", %{
             error_code: :invalid_input,
             format: format,
             supported_formats: @supported_formats
           })}

        present_domain_rules?(opts[:allowed_domains]) and present_domain_rules?(opts[:blocked_domains]) ->
          {:error,
           Error.invalid_error("Use either allowed_domains or blocked_domains, not both", %{
             error_code: :invalid_input
           })}

        format == :html and focus_terms != [] ->
          {:error,
           Error.invalid_error("Focused filtering is only supported for markdown and text output", %{
             error_code: :invalid_input,
             format: format
           })}

        true ->
          normalized =
            opts
            |> Keyword.put(:backend, backend)
            |> Keyword.put(:req, Keyword.merge(configured_req_opts, request_req_opts))
            |> Keyword.put(:browsey, Keyword.merge(configured_browsey_opts, request_browsey_opts))
            |> Keyword.put(:format, format)
            |> Keyword.put(:selector, selector)
            |> Keyword.put(:citations, citations)
            |> Keyword.put(:focus_terms, focus_terms)
            |> Keyword.put(:focus_window, focus_window)
            |> Keyword.put(:timeout, timeout)
            |> Keyword.put(:max_redirects, max_redirects)
            |> Keyword.put(:cache, cache)
            |> Keyword.put(:allow_private_network, allow_private_network)
            |> Keyword.put(:cache_ttl_ms, cache_ttl_ms)
            |> Keyword.put(:require_known_url, require_known_url)
            |> Keyword.put(:extractous, merge_extractous_opts(configured_extractous_opts, request_extractous_opts))
            |> maybe_put(:max_content_tokens, max_content_tokens)
            |> maybe_put(:max_url_length, max_url_length)
            |> Keyword.put_new(:known_urls, [])

          {:ok, normalized}
      end
    end
  end

  defp validate_url(url, opts) do
    normalized_url = String.trim(url)
    max_url_length = opts[:max_url_length] || @default_max_url_length

    with :ok <- validate_url_length(normalized_url, max_url_length),
         {:ok, uri} <- parse_fetch_uri(normalized_url),
         :ok <- validate_uri_host(uri) do
      {:ok, URI.to_string(uri), normalize_uri(uri)}
    end
  end

  defp normalize_max_redirects(opts, backend, configured_req_opts, request_req_opts) do
    req_opts = Keyword.merge(configured_req_opts, request_req_opts)

    value =
      case Keyword.fetch(opts, :max_redirects) do
        {:ok, top_level_value} -> top_level_value
        :error -> backend_redirect_limit(backend, req_opts)
      end

    normalize_integer_opt(:max_redirects, value, min: 0)
  end

  defp backend_redirect_limit(Jido.Browser.WebFetch.Backends.Req, req_opts) do
    Keyword.get(req_opts, :max_redirects, @default_req_max_redirects)
  end

  defp backend_redirect_limit(Jido.Browser.WebFetch.Backends.Browsey, _req_opts) do
    @default_browsey_max_redirects
  end

  defp backend_redirect_limit(_backend, req_opts) do
    Keyword.get(req_opts, :max_redirects, @default_req_max_redirects)
  end

  defp validate_known_url(url, opts) do
    known_urls =
      opts[:known_urls]
      |> List.wrap()
      |> Enum.map(&normalize_known_url/1)
      |> Enum.reject(&is_nil/1)

    if Keyword.get(opts, :require_known_url, false) do
      if url in known_urls do
        :ok
      else
        {:error,
         Error.invalid_error("Web fetch URL must already be present in tool context", %{
           error_code: :url_not_allowed,
           url: url
         })}
      end
    else
      :ok
    end
  end

  defp validate_domain_filters(%URI{} = uri, opts) do
    with {:ok, allowed_rules} <- normalize_domain_rules(opts[:allowed_domains]),
         {:ok, blocked_rules} <- normalize_domain_rules(opts[:blocked_domains]) do
      cond do
        allowed_rules != [] and not Enum.any?(allowed_rules, &rule_matches?(&1, uri)) ->
          {:error,
           Error.invalid_error("URL is not permitted by allowed_domains", %{
             error_code: :url_not_allowed,
             url: URI.to_string(uri)
           })}

        blocked_rules != [] and Enum.any?(blocked_rules, &rule_matches?(&1, uri)) ->
          {:error,
           Error.invalid_error("URL is blocked by blocked_domains", %{
             error_code: :url_not_allowed,
             url: URI.to_string(uri)
           })}

        true ->
          :ok
      end
    end
  end

  defp prepare_destination(url, opts) do
    uri = URI.parse(url)

    case validate_pinnable_backend(opts) do
      :ok ->
        with {:ok, addresses} <- resolve_destination_addresses(uri.host, opts),
             :ok <- maybe_validate_destination_addresses(addresses, url, opts) do
          {:ok, Keyword.put(opts, :destination_addresses, addresses)}
        end

      {:error, _reason} = error ->
        if opts[:allow_private_network] do
          {:ok, Keyword.delete(opts, :destination_address)}
        else
          error
        end
    end
  end

  defp fetch_prepared_destination(backend, url, opts) do
    case Keyword.pop(opts, :destination_addresses) do
      {nil, request_opts} -> backend.fetch(url, request_opts)
      {addresses, request_opts} -> fetch_destination_addresses(backend, url, request_opts, addresses)
    end
  end

  defp fetch_destination_addresses(backend, url, opts, [address | remaining]) do
    case backend.fetch(url, Keyword.put(opts, :destination_address, address)) do
      {:error, error} = result when remaining != [] ->
        if retryable_destination_error?(error) do
          fetch_destination_addresses(backend, url, opts, remaining)
        else
          result
        end

      result ->
        result
    end
  end

  defp retryable_destination_error?(%Error.AdapterError{
         details: %{reason: %Jido.Browser.Vendor.BrowseyHttp.ConnectionException{error_code: 7}}
       }),
       do: true

  defp retryable_destination_error?(%Error.AdapterError{
         details: %{reason: %Req.TransportError{reason: reason}}
       })
       when reason in [:econnrefused, :enetunreach, :ehostunreach, :eaddrnotavail],
       do: true

  defp retryable_destination_error?(_error), do: false

  defp maybe_validate_destination_addresses(addresses, url, opts) do
    if opts[:allow_private_network], do: :ok, else: validate_destination_addresses(addresses, url)
  end

  defp validate_pinnable_backend(opts) do
    backend = opts[:backend]

    validate_pinnable_backend(backend, opts)
  end

  defp validate_pinnable_backend(backend, opts)
       when backend in [Jido.Browser.WebFetch.Backends.Req, Jido.Browser.WebFetch.Backends.Browsey] do
    if backend == Jido.Browser.WebFetch.Backends.Req and req_uses_proxy?(opts[:req]) do
      destination_policy_error("Web fetch proxy settings require allow_private_network", %{
        backend: backend
      })
    else
      :ok
    end
  end

  defp validate_pinnable_backend(backend, _opts) do
    destination_policy_error("Web fetch backend cannot enforce destination address pinning", %{
      backend: backend
    })
  end

  defp req_uses_proxy?(req_opts) when is_list(req_opts) do
    case Keyword.get(req_opts, :connect_options, []) do
      connect_options when is_list(connect_options) -> Keyword.has_key?(connect_options, :proxy)
      _other -> false
    end
  end

  defp req_uses_proxy?(_req_opts), do: false

  defp resolve_destination_addresses(host, opts) do
    case parse_address(host) do
      {:ok, address} ->
        {:ok, [address]}

      :error ->
        host
        |> run_resolver(opts[:resolver] || config(:resolver, nil))
        |> normalize_resolver_result(host)
    end
  end

  defp run_resolver(host, nil), do: system_resolve(host)
  defp run_resolver(host, resolver) when is_function(resolver, 1), do: resolver.(host)

  defp run_resolver(host, resolver) when is_atom(resolver) do
    if Code.ensure_loaded?(resolver) and function_exported?(resolver, :resolve, 1) do
      resolver.resolve(host)
    else
      {:error, {:invalid_resolver, resolver}}
    end
  end

  defp run_resolver(_host, resolver), do: {:error, {:invalid_resolver, resolver}}

  defp system_resolve(host) do
    encoded_host = String.to_charlist(host)
    ipv4_result = :inet.getaddrs(encoded_host, :inet)
    ipv6_result = :inet.getaddrs(encoded_host, :inet6)

    addresses =
      [ipv4_result, ipv6_result]
      |> Enum.flat_map(fn
        {:ok, values} -> values
        {:error, _reason} -> []
      end)

    case addresses do
      [] -> {:error, {ipv4_result, ipv6_result}}
      values -> {:ok, values}
    end
  end

  defp normalize_resolver_result({:ok, addresses}, host) do
    addresses = addresses |> List.wrap() |> Enum.uniq()

    cond do
      addresses == [] ->
        destination_policy_error("Web fetch destination did not resolve to an address", %{host: host})

      Enum.all?(addresses, &valid_address?/1) ->
        {:ok, addresses}

      true ->
        destination_policy_error("Web fetch resolver returned an invalid address", %{
          host: host,
          addresses: addresses
        })
    end
  end

  defp normalize_resolver_result({:error, reason}, host) do
    destination_policy_error("Web fetch destination could not be resolved", %{
      host: host,
      reason: reason
    })
  end

  defp normalize_resolver_result(result, host) do
    destination_policy_error("Web fetch resolver returned an invalid result", %{
      host: host,
      result: result
    })
  end

  defp validate_destination_addresses(addresses, url) do
    case Enum.find(addresses, &blocked_address?/1) do
      nil ->
        :ok

      address ->
        destination_policy_error("Web fetch destination address is not allowed", %{
          url: url,
          address: address_to_string(address),
          policy_reason: blocked_address_reason(address)
        })
    end
  end

  defp blocked_address?(address), do: not is_nil(blocked_address_reason(address))

  defp parse_address(host) when is_binary(host) do
    case :inet.parse_address(String.to_charlist(host)) do
      {:ok, address} -> {:ok, address}
      {:error, :einval} -> :error
    end
  end

  defp valid_address?({a, b, c, d}) do
    Enum.all?([a, b, c, d], &integer_in_range?(&1, 0, 0xFF))
  end

  defp valid_address?({a, b, c, d, e, f, g, h}) do
    Enum.all?([a, b, c, d, e, f, g, h], &integer_in_range?(&1, 0, 0xFFFF))
  end

  defp valid_address?(_address), do: false

  defp integer_in_range?(value, minimum, maximum) do
    is_integer(value) and value >= minimum and value <= maximum
  end

  defp blocked_address_reason({100, 100, 100, 200}), do: :cloud_metadata

  defp blocked_address_reason({_a, _b, _c, _d} = address) do
    range_reason(address, @ipv4_special_ranges)
  end

  defp blocked_address_reason({0xFD00, 0x0EC2, 0, 0, 0, 0, 0, 0x0254}),
    do: :cloud_metadata

  defp blocked_address_reason({_a, _b, _c, _d, _e, _f, _g, _h} = address) do
    case range_reason(address, @ipv6_special_ranges) do
      nil -> if address_in_range?(address, @ipv6_global_unicast), do: nil, else: :non_global
      reason -> reason
    end
  end

  defp blocked_address_reason(_address), do: nil

  defp range_reason(address, ranges) do
    Enum.find_value(ranges, fn {prefix, prefix_length, reason} ->
      if address_in_range?(address, {prefix, prefix_length}), do: reason
    end)
  end

  defp address_in_range?(address, {prefix, prefix_length}) do
    {address_value, bit_count} = address_integer(address)
    {prefix_value, ^bit_count} = address_integer(prefix)
    shift = bit_count - prefix_length
    bsr(address_value, shift) == bsr(prefix_value, shift)
  end

  defp address_integer({_a, _b, _c, _d} = address) do
    {join_address_parts(Tuple.to_list(address), 8), 32}
  end

  defp address_integer({_a, _b, _c, _d, _e, _f, _g, _h} = address) do
    {join_address_parts(Tuple.to_list(address), 16), 128}
  end

  defp join_address_parts(parts, part_bits) do
    Enum.reduce(parts, 0, fn part, value -> bsl(value, part_bits) + part end)
  end

  defp address_to_string(address) do
    address
    |> :inet.ntoa()
    |> to_string()
  end

  defp destination_policy_error(message, details) do
    {:error, Error.invalid_error(message, Map.put(details, :error_code, @policy_error_code))}
  end

  defp normalize_domain_rules(nil), do: {:ok, []}

  defp normalize_domain_rules(rules) do
    rules
    |> List.wrap()
    |> Enum.reduce_while({:ok, []}, fn rule, {:ok, acc} ->
      case normalize_domain_rule(rule) do
        {:ok, normalized} -> {:cont, {:ok, [normalized | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, normalized} -> {:ok, Enum.reverse(normalized)}
      error -> error
    end
  end

  defp normalize_domain_rule(rule) when is_binary(rule) do
    normalized = String.trim(rule)

    cond do
      normalized == "" ->
        {:error, Error.invalid_error("Domain rules cannot be empty", %{error_code: :invalid_input})}

      String.contains?(normalized, "://") ->
        {:error,
         Error.invalid_error("Domain rules must not include URL schemes", %{
           error_code: :invalid_input,
           rule: normalized
         })}

      true ->
        uri = URI.parse("https://" <> normalized)
        host = String.downcase(uri.host || "")
        path = uri.path || "/"

        cond do
          host == "" ->
            {:error,
             Error.invalid_error("Domain rule must include a host", %{error_code: :invalid_input, rule: normalized})}

          not ascii_only?(host) ->
            {:error,
             Error.invalid_error("Domain rules must use ASCII hosts", %{
               error_code: :invalid_input,
               rule: normalized
             })}

          true ->
            {:ok, %{host: host, path: normalize_rule_path(path)}}
        end
    end
  end

  defp normalize_domain_rule(rule) do
    {:error, Error.invalid_error("Domain rule must be a string", %{error_code: :invalid_input, rule: rule})}
  end

  defp rule_matches?(%{host: host, path: path}, %URI{host: uri_host} = uri) do
    uri_host = String.downcase(uri_host)
    request_path = normalize_rule_path(uri.path || "/")

    host_matches? = uri_host == host or String.ends_with?(uri_host, "." <> host)
    path_matches? = path == "/" or String.starts_with?(request_path, path)

    host_matches? and path_matches?
  end

  defp normalize_final_url(%{final_url: final_url}) when is_binary(final_url) do
    with {:ok, uri} <- parse_fetch_uri(final_url),
         :ok <- validate_uri_host(uri) do
      normalized = normalize_uri(uri)
      {:ok, URI.to_string(normalized), normalized}
    end
  end

  defp normalize_final_url(response) do
    {:error,
     Error.adapter_error("Web fetch backend returned an invalid final URL", %{
       error_code: :unavailable,
       response: response
     })}
  end

  defp validate_http_status(%{status: status}, _url) when status in 200..299, do: :ok

  defp validate_http_status(%{status: 429}, _url) do
    {:error, Error.adapter_error("Web fetch rate limited", %{error_code: :too_many_requests, status: 429})}
  end

  defp validate_http_status(%{status: status}, url) do
    {:error,
     Error.adapter_error("Web fetch returned an HTTP error", %{
       error_code: :url_not_accessible,
       status: status,
       url: url
     })}
  end

  defp parse_document(body) do
    case Floki.parse_document(body) do
      {:ok, document} ->
        {:ok, document}

      {:error, reason} ->
        {:error, Error.adapter_error("Failed to parse fetched HTML", %{error_code: :unavailable, reason: reason})}
    end
  end

  defp select_html(_document, body, nil), do: {:ok, body}
  defp select_html(document, _body, ""), do: select_html(document, nil, nil)

  defp select_html(document, _body, selector) do
    nodes = Floki.find(document, selector)

    if nodes == [] do
      {:error,
       Error.invalid_error("Selector did not match any elements in fetched HTML", %{
         error_code: :invalid_input,
         selector: selector
       })}
    else
      {:ok, Floki.raw_html(nodes)}
    end
  end

  defp extract_title(document) do
    title =
      document
      |> Floki.find("title")
      |> Floki.text(sep: " ")
      |> String.trim()
      |> blank_to_nil()

    {:ok, title}
  end

  defp format_html(html, :html, _opts), do: {:ok, html}

  defp format_html(html, :text, _opts) do
    with {:ok, fragment} <- parse_fragment(html) do
      {:ok, fragment |> Floki.text(sep: "\n") |> String.trim()}
    end
  end

  defp format_html(html, :markdown, _opts) do
    {:ok, Html2Markdown.convert(html) |> String.trim()}
  rescue
    error ->
      {:error,
       Error.adapter_error("Failed to convert fetched HTML to markdown", %{error_code: :unavailable, reason: error})}
  end

  defp format_text(text, :text), do: {:ok, String.trim(text)}
  defp format_text(text, :markdown), do: {:ok, String.trim(text)}

  defp format_text(_text, :html) do
    {:error,
     Error.invalid_error("HTML output is only supported for HTML content", %{
       error_code: :invalid_input
     })}
  end

  defp parse_fragment(html) do
    case Floki.parse_fragment(html) do
      {:ok, fragment} ->
        {:ok, fragment}

      {:error, reason} ->
        {:error,
         Error.adapter_error("Failed to parse fetched HTML fragment", %{error_code: :unavailable, reason: reason})}
    end
  end

  defp maybe_filter_content(content, opts) do
    case opts[:focus_terms] do
      [] ->
        {:ok, content, false, 0}

      terms ->
        sections = split_sections(content)
        matching_indexes = matching_section_indexes(sections, terms)
        window = max(opts[:focus_window] || 0, 0)
        kept_indexes = expand_focus_window(matching_indexes, window, length(sections))
        filtered_content = render_section_slice(sections, kept_indexes)

        {:ok, filtered_content, true, length(matching_indexes)}
    end
  end

  defp maybe_truncate(content, nil), do: {content, false, estimate_tokens(content)}

  defp maybe_truncate(content, max_content_tokens) when is_integer(max_content_tokens) and max_content_tokens > 0 do
    original_estimated_tokens = estimate_tokens(content)

    if original_estimated_tokens <= max_content_tokens do
      {content, false, original_estimated_tokens}
    else
      char_limit = max_content_tokens * 4
      truncated = String.slice(content, 0, char_limit) |> String.trim()
      {truncated, true, original_estimated_tokens}
    end
  end

  defp maybe_truncate(content, _other), do: {content, false, estimate_tokens(content)}

  defp maybe_build_passages(_content, _title, _url, false), do: []

  defp maybe_build_passages(content, title, url, true) do
    content
    |> split_sections()
    |> Enum.reject(&(&1 == ""))
    |> Enum.reduce({[], 0, 0}, fn section, {passages, cursor, index} ->
      start_char = cursor
      end_char = start_char + String.length(section)

      passage = %{
        index: index,
        start_char: start_char,
        end_char: end_char,
        text: section,
        title: title,
        url: url
      }

      {[passage | passages], end_char + 2, index + 1}
    end)
    |> elem(0)
    |> Enum.reverse()
    |> Enum.take(50)
  end

  defp split_sections(content) do
    content
    |> String.split(~r/\n\s*\n+/, trim: true)
    |> case do
      [] -> [String.trim(content)]
      sections -> Enum.map(sections, &String.trim/1)
    end
  end

  defp extract_document_content(bytes, final_url, content_type, document_type, opts) do
    case ExtractousEx.extract_from_bytes(bytes, opts[:extractous]) do
      {:ok, %{content: content, metadata: metadata}} when is_binary(content) ->
        {:ok, String.trim(content), normalize_metadata(metadata)}

      {:error, reason} ->
        {:error,
         Error.adapter_error("ExtractousEx failed while extracting document content", %{
           error_code: :unavailable,
           url: final_url,
           content_type: content_type,
           document_type: document_type,
           reason: reason
         })}
    end
  rescue
    error ->
      {:error,
       Error.adapter_error("ExtractousEx failed while extracting document content", %{
         error_code: :unavailable,
         url: final_url,
         content_type: content_type,
         document_type: document_type,
         reason: error
       })}
  end

  defp fetch_cached(url, opts) do
    if opts[:cache] do
      ensure_cache_table!()
      lookup_cached_result(cache_key(url, opts), System.system_time(:millisecond))
    else
      :miss
    end
  end

  defp lookup_cached_result(key, now) do
    case :ets.lookup(@cache_table, key) do
      [{_key, expires_at, result}] -> handle_cached_result(key, expires_at, result, now)
      [] -> :miss
    end
  end

  defp handle_cached_result(_key, expires_at, result, now) when expires_at > now do
    {:ok, Map.put(result, :cached, true)}
  end

  defp handle_cached_result(key, _expires_at, _result, _now) do
    :ets.delete(@cache_table, key)
    :miss
  end

  defp maybe_store_cache(url, opts, result) do
    if opts[:cache] do
      ensure_cache_table!()

      expires_at = System.system_time(:millisecond) + max(opts[:cache_ttl_ms], 0)
      :ets.insert(@cache_table, {cache_key(url, opts), expires_at, result})
    end

    :ok
  end

  defp ensure_cache_table! do
    case :ets.whereis(@cache_table) do
      :undefined ->
        try do
          :ets.new(@cache_table, [:named_table, :set, :public, read_concurrency: true, write_concurrency: true])
        rescue
          ArgumentError -> @cache_table
        end

      table ->
        table
    end
  end

  defp cache_key(url, opts) do
    {:jido_browser_web_fetch, url, opts[:format], opts[:selector], opts[:allowed_domains], opts[:blocked_domains],
     opts[:focus_terms], opts[:focus_window], opts[:max_content_tokens], opts[:citations], opts[:extractous],
     opts[:backend], opts[:req], opts[:browsey], opts[:allow_private_network]}
  end

  defp response_content_type(response) do
    response.headers
    |> response_header("content-type")
    |> List.first()
    |> case do
      nil -> infer_content_type(response.body)
      content_type -> content_type |> String.split(";") |> hd() |> String.trim() |> String.downcase()
    end
  end

  defp response_header(headers, name) when is_map(headers) do
    headers
    |> Map.get(name, Map.get(headers, String.downcase(name), []))
    |> List.wrap()
  end

  defp infer_content_type(body) when is_binary(body) do
    cond do
      String.starts_with?(body, "%PDF-") ->
        "application/pdf"

      likely_text?(body) ->
        "text/plain"

      true ->
        "application/octet-stream"
    end
  end

  defp infer_content_type(_body), do: "application/octet-stream"

  defp text_content_type?(content_type) do
    content_type in @text_content_types or String.starts_with?(content_type, "text/")
  end

  defp retrieved_at do
    DateTime.utc_now()
    |> DateTime.truncate(:second)
    |> DateTime.to_iso8601()
  end

  defp estimate_tokens(content) when is_binary(content) do
    div(String.length(content) + 3, 4)
  end

  defp estimate_tokens(_content), do: 0

  defp normalize_citations(%{enabled: enabled}), do: enabled == true
  defp normalize_citations(enabled), do: enabled == true

  defp present_domain_rules?(rules), do: rules not in [nil, []]

  defp normalize_focus_terms(nil), do: []

  defp normalize_focus_terms(terms) do
    terms
    |> List.wrap()
    |> Enum.map(fn
      term when is_binary(term) -> String.trim(term)
      term -> to_string(term)
    end)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp normalize_backend(:req), do: normalize_backend(Jido.Browser.WebFetch.Backends.Req)
  defp normalize_backend(:browsey), do: normalize_backend(Jido.Browser.WebFetch.Backends.Browsey)

  defp normalize_backend(backend) when is_atom(backend) and not is_nil(backend) do
    if Code.ensure_loaded?(backend) and function_exported?(backend, :fetch, 2) do
      {:ok, backend}
    else
      {:error,
       Error.invalid_error("Web fetch backend must implement fetch/2", %{
         error_code: :invalid_input,
         backend: backend
       })}
    end
  end

  defp normalize_backend(backend) do
    {:error,
     Error.invalid_error("Web fetch backend must be :req, :browsey, or a backend module", %{
       error_code: :invalid_input,
       backend: backend
     })}
  end

  defp normalize_backend_opts(_name, nil), do: {:ok, []}

  defp normalize_backend_opts(_name, opts) when is_list(opts) do
    if Keyword.keyword?(opts) do
      {:ok, canonicalize_keyword_list(opts)}
    else
      {:error,
       Error.invalid_error("Web fetch backend options must be a keyword list", %{
         error_code: :invalid_input,
         backend_options: opts
       })}
    end
  end

  defp normalize_backend_opts(name, opts) do
    {:error,
     Error.invalid_error("Web fetch backend options must be a keyword list", %{
       error_code: :invalid_input,
       option: name,
       backend_options: opts
     })}
  end

  defp normalize_extractous_opts(nil), do: {:ok, []}

  defp normalize_extractous_opts(opts) when is_list(opts) do
    if Keyword.keyword?(opts) do
      {:ok, canonicalize_keyword_list(opts)}
    else
      {:error,
       Error.invalid_error("Extractous options must be a keyword list", %{
         error_code: :invalid_input,
         extractous: opts
       })}
    end
  end

  defp normalize_extractous_opts(opts) do
    {:error,
     Error.invalid_error("Extractous options must be a keyword list", %{
       error_code: :invalid_input,
       extractous: opts
     })}
  end

  defp normalize_selector(nil), do: {:ok, nil}

  defp normalize_selector(selector) when is_binary(selector) do
    selector
    |> String.trim()
    |> case do
      "" -> {:ok, nil}
      value -> {:ok, value}
    end
  end

  defp normalize_selector(selector) do
    {:error,
     Error.invalid_error("Selector must be a string", %{
       error_code: :invalid_input,
       selector: selector
     })}
  end

  defp validate_url_length("", _max_url_length) do
    {:error, Error.invalid_error("URL cannot be empty", %{error_code: :invalid_input})}
  end

  defp validate_url_length(normalized_url, max_url_length) do
    if String.length(normalized_url) > max_url_length do
      {:error,
       Error.invalid_error("URL exceeds maximum length", %{
         error_code: :url_too_long,
         max_url_length: max_url_length
       })}
    else
      :ok
    end
  end

  defp parse_fetch_uri(normalized_url) do
    uri = URI.parse(normalized_url)

    if uri.scheme in ["http", "https"] do
      {:ok, uri}
    else
      {:error,
       Error.invalid_error("Web fetch only supports http and https URLs", %{
         error_code: :invalid_input,
         scheme: uri.scheme
       })}
    end
  end

  defp validate_uri_host(%URI{host: host}) when host in [nil, ""] do
    {:error, Error.invalid_error("URL must include a host", %{error_code: :invalid_input})}
  end

  defp validate_uri_host(%URI{host: host}) do
    if ascii_only?(host) do
      :ok
    else
      {:error,
       Error.invalid_error("Web fetch only accepts ASCII hostnames", %{
         error_code: :url_not_allowed,
         host: host
       })}
    end
  end

  defp normalize_integer_opt(_name, value, min: min) when is_integer(value) and value >= min, do: {:ok, value}

  defp normalize_integer_opt(name, value, min: min) do
    {:error,
     Error.invalid_error("#{name} must be an integer greater than or equal to #{min}", %{
       error_code: :invalid_input,
       option: name,
       value: value
     })}
  end

  defp normalize_optional_integer_opt(_name, nil, _opts), do: {:ok, nil}
  defp normalize_optional_integer_opt(name, value, opts), do: normalize_integer_opt(name, value, opts)

  defp normalize_boolean_opt(_name, value) when is_boolean(value), do: {:ok, value}

  defp normalize_boolean_opt(name, value) do
    {:error,
     Error.invalid_error("#{name} must be a boolean", %{
       error_code: :invalid_input,
       option: name,
       value: value
     })}
  end

  defp canonicalize_keyword_list(keyword_list) do
    keyword_list
    |> Enum.map(fn {key, value} = pair ->
      if is_list(value) and Keyword.keyword?(value) do
        {key, canonicalize_keyword_list(value)}
      else
        pair
      end
    end)
    |> Enum.sort_by(fn {key, _value} -> to_string(key) end)
  end

  defp merge_extractous_opts(left, right) do
    Keyword.merge(left, right, fn _key, left_value, right_value ->
      if Keyword.keyword?(left_value) and Keyword.keyword?(right_value) do
        merge_extractous_opts(left_value, right_value)
      else
        right_value
      end
    end)
  end

  defp normalize_known_url(url) when is_binary(url) do
    url
    |> String.trim()
    |> case do
      "" -> nil
      value -> value
    end
  end

  defp normalize_known_url(_), do: nil

  defp normalize_uri(%URI{} = uri) do
    %{uri | host: String.downcase(uri.host || ""), fragment: nil}
  end

  defp normalize_rule_path(""), do: "/"
  defp normalize_rule_path(path), do: if(String.starts_with?(path, "/"), do: path, else: "/" <> path)

  defp extractable_document_type(content_type, final_url, body) do
    Map.get(@document_content_types, content_type) ||
      infer_document_type_from_body(body) ||
      if(ambiguous_binary_content_type?(content_type), do: infer_document_type_from_url(final_url), else: nil)
  end

  defp infer_document_type_from_url(url) do
    url
    |> URI.parse()
    |> Map.get(:path, "")
    |> Path.extname()
    |> String.trim_leading(".")
    |> String.downcase()
    |> case do
      "" -> nil
      extension -> Map.get(@document_extensions, extension)
    end
  end

  defp infer_document_type_from_body(body) when is_binary(body) do
    if String.starts_with?(body, "%PDF-"), do: :pdf, else: nil
  end

  defp infer_document_type_from_body(_body), do: nil

  defp document_title(metadata, url) do
    metadata
    |> metadata_title()
    |> blank_to_nil()
    |> case do
      nil -> title_from_url(url)
      title -> title
    end
  end

  defp metadata_title(metadata) when is_map(metadata) do
    Enum.find_value([:title, "title", "dc:title", :"dc:title"], fn key ->
      metadata
      |> Map.get(key)
      |> metadata_value_to_string()
      |> blank_to_nil()
    end)
  end

  defp metadata_value_to_string(nil), do: nil
  defp metadata_value_to_string(value) when is_binary(value), do: String.trim(value)

  defp metadata_value_to_string(value) when is_list(value),
    do: value |> Enum.map_join(" ", &to_string/1) |> String.trim()

  defp metadata_value_to_string(value) when is_atom(value), do: value |> Atom.to_string() |> String.trim()
  defp metadata_value_to_string(value) when is_number(value), do: value |> to_string() |> String.trim()
  defp metadata_value_to_string(_value), do: nil

  defp normalize_metadata(metadata) when is_map(metadata), do: metadata

  defp maybe_put_metadata(response, metadata) when metadata in [%{}, nil], do: response
  defp maybe_put_metadata(response, metadata), do: Map.put(response, :metadata, metadata)
  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp matching_section_indexes(sections, terms) do
    downcased_terms = Enum.map(terms, &String.downcase/1)

    sections
    |> Enum.with_index()
    |> Enum.flat_map(fn {section, index} ->
      if section_matches_term?(section, downcased_terms), do: [index], else: []
    end)
  end

  defp section_matches_term?(section, downcased_terms) do
    lowered = String.downcase(section)
    Enum.any?(downcased_terms, &String.contains?(lowered, &1))
  end

  defp expand_focus_window(matching_indexes, window, section_count) do
    matching_indexes
    |> Enum.flat_map(fn index -> (index - window)..(index + window) end)
    |> Enum.filter(&(&1 >= 0 and &1 < section_count))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp render_section_slice(sections, indexes) do
    indexes
    |> Enum.map(&Enum.at(sections, &1))
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n\n")
    |> String.trim()
  end

  defp title_from_url(url) do
    path = URI.parse(url).path || ""

    case path do
      "" -> nil
      "/" -> nil
      value -> value |> Path.basename() |> String.trim("/") |> blank_to_nil()
    end
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp ascii_only?(value) when is_binary(value) do
    String.printable?(value) and String.match?(value, ~r/^[\x00-\x7F]+$/)
  end

  defp ambiguous_binary_content_type?(content_type) do
    content_type in [
      "application/octet-stream",
      "binary/octet-stream",
      "application/download",
      "application/x-download",
      "application/zip",
      "application/x-zip-compressed"
    ]
  end

  defp likely_text?(body) when is_binary(body) do
    String.valid?(body) and not String.contains?(body, <<0>>)
  end

  defp config(key, default) do
    :jido_browser
    |> Application.get_env(:web_fetch, [])
    |> Keyword.get(key, default)
  end
end
