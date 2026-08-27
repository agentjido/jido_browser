defmodule Jido.Browser.WebFetch do
  @moduledoc """
  Stateless HTTP-first web retrieval with optional domain policy, caching,
  focused filtering, citation-ready passage metadata, and Extractous-backed
  document extraction.

  This module is intended for document retrieval workloads where starting a full
  browser session would be unnecessary or too expensive.
  """

  alias Jido.Browser.Error
  alias Jido.Browser.WebFetch.Cache
  alias Jido.Browser.WebFetch.DestinationPolicy
  alias Jido.Browser.WebFetch.Options
  alias Jido.Browser.WebFetch.URLRules

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
  - `:max_response_bytes` - response cap in bytes, defaults to 5 MiB; Req
    applies it to both the transfer body and each decoded content layer, while
    Browsey applies it to curl's decoded output; use `:infinity` only as an
    explicit compatibility override
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
    with {:ok, opts} <- Options.normalize(opts),
         {:ok, normalized_url, uri} <- URLRules.validate(url, opts),
         :ok <- URLRules.validate_known(normalized_url, opts),
         :ok <- URLRules.validate_domain_filters(uri, opts) do
      case Cache.fetch(normalized_url, opts) do
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
  def clear_cache, do: Cache.clear()

  defp do_fetch(url, opts) do
    with {:ok, request_opts, cookie_file} <- prepare_redirect_chain(opts) do
      try do
        with {:ok, response, final_url, _final_uri} <- fetch_with_redirects(url, request_opts),
             :ok <- validate_http_status(response, url),
             {:ok, result} <- build_result(url, final_url, response, request_opts) do
          Cache.store(url, request_opts, result)
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

      case URLRules.validate(transformed_url, request_opts) do
        {:ok, normalized_url, _uri} -> {:ok, normalized_url, request_opts}
        {:error, _reason} = error -> error
      end
    else
      {:ok, url |> URI.parse() |> URLRules.normalize_uri() |> URI.to_string(), opts}
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

    with {:ok, request_opts} <- DestinationPolicy.prepare(current_url, opts),
         {:ok, response} <- fetch_prepared_destination(backend, current_url, request_opts),
         {:ok, response} <- ensure_backend_kept_request_url(response, current_url) do
      follow_redirect(response, current_url, opts, redirect_count)
    end
  end

  defp ensure_backend_kept_request_url(response, current_url) do
    expected_url = current_url |> URI.parse() |> URLRules.normalize_uri() |> URI.to_string()

    case URLRules.normalize_final_url(response) do
      {:ok, ^expected_url, _uri} ->
        {:ok, Map.put(response, :final_url, expected_url)}

      {:ok, backend_url, _uri} ->
        URLRules.destination_policy_error("Web fetch backend followed an unvalidated redirect", %{
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
      with {:ok, redirect_url, redirect_uri} <- URLRules.resolve_redirect_url(current_url, location, opts),
           :ok <- URLRules.validate_domain_filters(redirect_uri, opts),
           {:ok, redirect_opts} <-
             redirect_request_opts(opts, current_url, redirect_uri, response.status) do
        fetch_with_redirects(redirect_url, redirect_opts, redirect_count + 1)
      end
    end
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
    URLRules.destination_policy_error("Web fetch redirect location is not allowed", %{
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
    final_uri = final_url |> URI.parse() |> URLRules.normalize_uri()
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
end
