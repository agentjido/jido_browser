defmodule Jido.Browser.WebFetch do
  @moduledoc """
  Stateless HTTP-first web retrieval with optional domain policy, caching,
  focused filtering, citation-ready passage metadata, and Extractous-backed
  document extraction.

  This module is intended for document retrieval workloads where starting a full
  browser session would be unnecessary or too expensive.
  """

  alias Jido.Browser.Error

  @cache_table :jido_browser_web_fetch_cache
  @default_timeout 15_000
  @default_max_redirects 5
  @default_cache_ttl_ms 300_000
  @default_max_url_length 2_048
  @supported_formats [:markdown, :text, :html]
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
  - `:max_content_tokens` - approximate token cap
  - `:citations` - boolean, when true include passage spans
  - `:focus_terms` - list of terms used for focused filtering
  - `:focus_window` - paragraph window around focus matches
  - `:timeout` - receive timeout in milliseconds
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
    request_opts = [
      url: url,
      headers: request_headers(),
      receive_timeout: opts[:timeout],
      decode_body: false,
      redirect: true,
      max_redirects: opts[:max_redirects]
    ]

    case Req.run(request_opts) do
      {%Req.Request{} = request, %Req.Response{} = response} ->
        with :ok <- validate_http_status(response, url),
             {:ok, final_url, final_uri} <- normalize_final_url(request),
             :ok <- validate_domain_filters(final_uri, opts),
             {:ok, result} <- build_result(url, final_url, response, opts) do
          maybe_store_cache(url, opts, result)
          {:ok, result}
        end

      {_request, %Req.TransportError{} = exception} ->
        {:error, Error.adapter_error("Web fetch request failed", %{error_code: :url_not_accessible, reason: exception})}

      {_request, %Req.TooManyRedirectsError{} = exception} ->
        {:error,
         Error.adapter_error("Web fetch exceeded redirect limit", %{error_code: :url_not_accessible, reason: exception})}

      {_request, %_{} = exception} ->
        {:error, Error.adapter_error("Web fetch failed", %{error_code: :unavailable, reason: exception})}

      {_request, reason} ->
        {:error, Error.adapter_error("Web fetch failed", %{error_code: :unavailable, reason: reason})}
    end
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

  defp build_response(
         url,
         final_url,
         content,
         title,
         content_type,
         document_type,
         opts,
         truncated,
         filtered,
         focus_matches,
         original_estimated_tokens,
         metadata
       ) do
    passages = maybe_build_passages(content, title, final_url, opts[:citations])

    %{
      url: url,
      final_url: final_url,
      title: title,
      content: content,
      format: opts[:format],
      content_type: content_type,
      document_type: document_type,
      retrieved_at: retrieved_at(),
      estimated_tokens: estimate_tokens(content),
      original_estimated_tokens: original_estimated_tokens,
      truncated: truncated,
      filtered: filtered,
      focus_matches: focus_matches,
      cached: false,
      citations: %{enabled: opts[:citations]},
      passages: passages
    }
    |> maybe_put_metadata(metadata)
  end

  defp finalize_result(url, final_url, content, title, content_type, document_type, opts, metadata \\ nil) do
    with {:ok, filtered_content, filtered, focus_matches} <- maybe_filter_content(content, opts),
         {final_content, truncated, original_estimated_tokens} <-
           maybe_truncate(filtered_content, opts[:max_content_tokens]) do
      {:ok,
       build_response(
         url,
         final_url,
         final_content,
         title,
         content_type,
         document_type,
         opts,
         truncated,
         filtered,
         focus_matches,
         original_estimated_tokens,
         metadata
       )}
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

    with {:ok, configured_extractous_opts} <- normalize_extractous_opts(config(:extractous, [])),
         {:ok, request_extractous_opts} <- normalize_extractous_opts(Keyword.get(opts, :extractous, [])),
         {:ok, selector} <- normalize_selector(opts[:selector]),
         {:ok, focus_window} <- normalize_integer_opt(:focus_window, Keyword.get(opts, :focus_window, 0), min: 0),
         {:ok, timeout} <-
           normalize_integer_opt(:timeout, Keyword.get(opts, :timeout, config(:timeout, @default_timeout)), min: 1),
         {:ok, max_redirects} <-
           normalize_integer_opt(:max_redirects, Keyword.get(opts, :max_redirects, @default_max_redirects), min: 0),
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
            |> Keyword.put(:format, format)
            |> Keyword.put(:selector, selector)
            |> Keyword.put(:citations, citations)
            |> Keyword.put(:focus_terms, focus_terms)
            |> Keyword.put(:focus_window, focus_window)
            |> Keyword.put(:timeout, timeout)
            |> Keyword.put(:max_redirects, max_redirects)
            |> Keyword.put(:cache, cache)
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

    cond do
      normalized_url == "" ->
        {:error, Error.invalid_error("URL cannot be empty", %{error_code: :invalid_input})}

      String.length(normalized_url) > max_url_length ->
        {:error,
         Error.invalid_error("URL exceeds maximum length", %{
           error_code: :url_too_long,
           max_url_length: max_url_length
         })}

      true ->
        uri = URI.parse(normalized_url)

        cond do
          uri.scheme not in ["http", "https"] ->
            {:error,
             Error.invalid_error("Web fetch only supports http and https URLs", %{
               error_code: :invalid_input,
               scheme: uri.scheme
             })}

          is_nil(uri.host) or uri.host == "" ->
            {:error, Error.invalid_error("URL must include a host", %{error_code: :invalid_input})}

          not ascii_only?(uri.host) ->
            {:error,
             Error.invalid_error("Web fetch only accepts ASCII hostnames", %{
               error_code: :url_not_allowed,
               host: uri.host
             })}

          true ->
            {:ok, URI.to_string(uri), normalize_uri(uri)}
        end
    end
  end

  defp validate_known_url(url, opts) do
    known_urls =
      opts[:known_urls]
      |> List.wrap()
      |> Enum.map(&normalize_known_url/1)
      |> Enum.reject(&is_nil/1)

    if not Keyword.get(opts, :require_known_url, false) do
      :ok
    else
      if url in known_urls do
        :ok
      else
        {:error,
         Error.invalid_error("Web fetch URL must already be present in tool context", %{
           error_code: :url_not_allowed,
           url: url
         })}
      end
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
    uri_host = String.downcase(uri_host || "")
    request_path = normalize_rule_path(uri.path || "/")

    host_matches? = uri_host == host or String.ends_with?(uri_host, "." <> host)
    path_matches? = path == "/" or String.starts_with?(request_path, path)

    host_matches? and path_matches?
  end

  defp normalize_final_url(%Req.Request{url: %URI{} = uri}) do
    normalized = normalize_uri(uri)
    {:ok, URI.to_string(normalized), normalized}
  end

  defp validate_http_status(%Req.Response{status: status}, _url) when status in 200..299, do: :ok

  defp validate_http_status(%Req.Response{status: 429}, _url) do
    {:error, Error.adapter_error("Web fetch rate limited", %{error_code: :too_many_requests, status: 429})}
  end

  defp validate_http_status(%Req.Response{status: status}, url) do
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
        downcased_terms = Enum.map(terms, &String.downcase/1)

        matching_indexes =
          sections
          |> Enum.with_index()
          |> Enum.flat_map(fn {section, index} ->
            lowered = String.downcase(section)

            if Enum.any?(downcased_terms, &String.contains?(lowered, &1)) do
              [index]
            else
              []
            end
          end)

        window = max(opts[:focus_window] || 0, 0)

        kept_indexes =
          matching_indexes
          |> Enum.flat_map(fn index -> (index - window)..(index + window) end)
          |> Enum.filter(&(&1 >= 0 and &1 < length(sections)))
          |> Enum.uniq()
          |> Enum.sort()

        filtered_content =
          kept_indexes
          |> Enum.map(&Enum.at(sections, &1))
          |> Enum.reject(&(&1 == ""))
          |> Enum.join("\n\n")
          |> String.trim()

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

      {:ok, %{content: content}} when is_binary(content) ->
        {:ok, String.trim(content), %{}}

      {:ok, result} ->
        {:error,
         Error.adapter_error("ExtractousEx returned an unexpected document payload", %{
           error_code: :unavailable,
           url: final_url,
           content_type: content_type,
           document_type: document_type,
           result: result
         })}

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
      now = System.system_time(:millisecond)

      case :ets.lookup(@cache_table, cache_key(url, opts)) do
        [{_key, expires_at, result}] ->
          if expires_at > now do
            {:ok, Map.put(result, :cached, true)}
          else
            :ets.delete(@cache_table, cache_key(url, opts))
            :miss
          end

        [] ->
          :miss
      end
    else
      :miss
    end
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
     opts[:focus_terms], opts[:focus_window], opts[:max_content_tokens], opts[:citations], opts[:extractous]}
  end

  defp request_headers do
    [
      {"accept",
       "text/html,application/xhtml+xml,text/plain,application/json,application/pdf," <>
         "application/msword,application/vnd.openxmlformats-officedocument.wordprocessingml.document," <>
         "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet," <>
         "application/vnd.openxmlformats-officedocument.presentationml.presentation,*/*;q=0.1"},
      {"user-agent", user_agent()}
    ]
  end

  defp user_agent do
    vsn =
      case Application.spec(:jido_browser, :vsn) do
        nil -> "dev"
        value -> List.to_string(value)
      end

    "jido_browser/#{vsn}"
  end

  defp response_content_type(response) do
    response
    |> Req.Response.get_header("content-type")
    |> List.first()
    |> case do
      nil -> infer_content_type(response.body)
      content_type -> content_type |> String.split(";") |> hd() |> String.trim() |> String.downcase()
    end
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

  defp normalize_rule_path(nil), do: "/"
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

  defp metadata_title(_metadata), do: nil

  defp metadata_value_to_string(nil), do: nil
  defp metadata_value_to_string(value) when is_binary(value), do: String.trim(value)

  defp metadata_value_to_string(value) when is_list(value),
    do: value |> Enum.map_join(" ", &to_string/1) |> String.trim()

  defp metadata_value_to_string(value) when is_atom(value), do: value |> Atom.to_string() |> String.trim()
  defp metadata_value_to_string(value) when is_number(value), do: value |> to_string() |> String.trim()
  defp metadata_value_to_string(_value), do: nil

  defp normalize_metadata(metadata) when is_map(metadata), do: metadata
  defp normalize_metadata(_metadata), do: %{}

  defp maybe_put_metadata(response, metadata) when metadata in [%{}, nil], do: response
  defp maybe_put_metadata(response, metadata), do: Map.put(response, :metadata, metadata)
  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

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
