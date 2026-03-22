defmodule Jido.Browser.WebFetch do
  @moduledoc """
  Stateless HTTP-first web retrieval with optional domain policy, caching,
  focused filtering, and citation-ready passage metadata.

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
  @text_content_types ["text/plain", "text/markdown", "text/csv", "text/xml", "application/xml"]
  @pdf_content_types ["application/pdf"]

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
          optional(:title) => String.t() | nil
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

    cond do
      content_type in @html_content_types ->
        build_html_result(url, final_url, response.body, content_type, opts)

      content_type in @pdf_content_types ->
        build_pdf_result(url, final_url, response.body, content_type, opts)

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
         {:ok, content} <- format_html(html, opts[:format], opts),
         {:ok, filtered_content, filtered, focus_matches} <- maybe_filter_content(content, opts),
         {final_content, truncated, original_estimated_tokens} <-
           maybe_truncate(filtered_content, opts[:max_content_tokens]) do
      {:ok,
       build_response(
         url,
         final_url,
         final_content,
         title,
         content_type,
         :html,
         opts,
         truncated,
         filtered,
         focus_matches,
         original_estimated_tokens
       )}
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
    if opts[:selector] do
      {:error,
       Error.invalid_error("Selector filtering is only supported for HTML content", %{
         error_code: :invalid_input,
         selector: opts[:selector],
         content_type: content_type
       })}
    else
      with {:ok, content} <- format_text(body, opts[:format]),
           {:ok, filtered_content, filtered, focus_matches} <- maybe_filter_content(content, opts),
           {final_content, truncated, original_estimated_tokens} <-
             maybe_truncate(filtered_content, opts[:max_content_tokens]) do
        {:ok,
         build_response(
           url,
           final_url,
           final_content,
           nil,
           content_type,
           :text,
           opts,
           truncated,
           filtered,
           focus_matches,
           original_estimated_tokens
         )}
      end
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

  defp build_pdf_result(url, final_url, body, content_type, opts) when is_binary(body) do
    cond do
      opts[:selector] ->
        {:error,
         Error.invalid_error("Selector filtering is not supported for PDF content", %{
           error_code: :invalid_input,
           selector: opts[:selector],
           content_type: content_type
         })}

      opts[:format] == :html ->
        {:error,
         Error.invalid_error("HTML output is not supported for PDF content", %{
           error_code: :invalid_input,
           format: :html,
           content_type: content_type
         })}

      true ->
        with {:ok, text} <- extract_pdf_text(body),
             {:ok, filtered_content, filtered, focus_matches} <- maybe_filter_content(text, opts),
             {final_content, truncated, original_estimated_tokens} <-
               maybe_truncate(filtered_content, opts[:max_content_tokens]) do
          {:ok,
           build_response(
             url,
             final_url,
             final_content,
             title_from_url(final_url),
             content_type,
             :pdf,
             opts,
             truncated,
             filtered,
             focus_matches,
             original_estimated_tokens
           )}
        end
    end
  end

  defp build_pdf_result(_url, _final_url, body, content_type, _opts) do
    {:error,
     Error.adapter_error("Unexpected response body for PDF fetch", %{
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
         original_estimated_tokens
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
  end

  defp normalize_opts(opts) do
    format = opts[:format] || :markdown
    citations = normalize_citations(opts[:citations])
    focus_terms = normalize_focus_terms(opts[:focus_terms])

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
          |> Keyword.put(:citations, citations)
          |> Keyword.put(:focus_terms, focus_terms)
          |> Keyword.put_new(:focus_window, 0)
          |> Keyword.put_new(:timeout, config(:timeout, @default_timeout))
          |> Keyword.put_new(:max_redirects, @default_max_redirects)
          |> Keyword.put_new(:cache, true)
          |> Keyword.put_new(:cache_ttl_ms, config(:cache_ttl_ms, @default_cache_ttl_ms))
          |> Keyword.put_new(:known_urls, [])

        {:ok, normalized}
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

  defp extract_pdf_text(bytes) do
    case pdftotext_path() do
      nil ->
        {:error,
         Error.adapter_error("PDF extraction requires pdftotext to be installed", %{
           error_code: :unsupported_content_type,
           content_type: "application/pdf"
         })}

      binary ->
        with_tmp_files("jido_browser_web_fetch", ".pdf", ".txt", fn pdf_path, txt_path ->
          File.write!(pdf_path, bytes)

          case System.cmd(binary, ["-layout", "-nopgbrk", pdf_path, txt_path], stderr_to_stdout: true) do
            {_output, 0} ->
              case File.read(txt_path) do
                {:ok, text} ->
                  {:ok, String.trim(text)}

                {:error, reason} ->
                  {:error,
                   Error.adapter_error("Failed to read extracted PDF text", %{error_code: :unavailable, reason: reason})}
              end

            {output, status} ->
              {:error,
               Error.adapter_error("pdftotext failed while extracting PDF", %{
                 error_code: :unavailable,
                 status: status,
                 output: output
               })}
          end
        end)
    end
  end

  defp pdftotext_path do
    config(:pdftotext_path) || System.find_executable("pdftotext")
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
     opts[:focus_terms], opts[:focus_window], opts[:max_content_tokens], opts[:citations]}
  end

  defp request_headers do
    [
      {"accept", "text/html,application/xhtml+xml,text/plain,application/pdf;q=0.9,*/*;q=0.1"},
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
    if String.starts_with?(body, "%PDF-") do
      "application/pdf"
    else
      "text/plain"
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

  defp config(key, default \\ nil) do
    :jido_browser
    |> Application.get_env(:web_fetch, [])
    |> Keyword.get(key, default)
  end

  defp with_tmp_files(prefix, first_suffix, second_suffix, fun) do
    base = Path.join(System.tmp_dir!(), "#{prefix}_#{System.unique_integer([:positive])}")
    first = base <> first_suffix
    second = base <> second_suffix

    try do
      fun.(first, second)
    after
      File.rm(first)
      File.rm(second)
    end
  end
end
