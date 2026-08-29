defmodule Jido.Browser.WebFetch do
  @moduledoc """
  Stateless HTTP-first web retrieval with optional domain policy, caching,
  focused filtering, citation-ready passage metadata, and optional
  Extractous-backed document extraction.

  This module is intended for document retrieval workloads where starting a full
  browser session would be unnecessary or too expensive.
  """

  alias Jido.Browser.Error
  alias Jido.Browser.Result, as: BrowserResult
  alias Jido.Browser.WebFetch.Cache
  alias Jido.Browser.WebFetch.Content
  alias Jido.Browser.WebFetch.DestinationPolicy
  alias Jido.Browser.WebFetch.Options
  alias Jido.Browser.WebFetch.Result
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
    applies it to both the transfer body and each decoded content layer; use
    `:infinity` only as an explicit compatibility override
  - `:max_content_tokens` - approximate token cap
  - `:citations` - boolean, when true include passage spans
  - `:focus_terms` - list of terms used for focused filtering
  - `:focus_window` - paragraph window around focus matches
  - `:timeout` - receive timeout in milliseconds
  - `:max_redirects` - redirect limit; overrides a nested Req limit
  - `:cache` - enable ETS cache, defaults to `true`
  - `:cache_ttl_ms` - cache TTL in milliseconds
  - `:require_known_url` / `:known_urls` - optional URL provenance guard
  - `:extractous` - keyword options for the optional `ExtractousEx` dependency,
    merged with config
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
          {:ok, BrowserResult.normalize(result)}

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
    with {:ok, response, final_url, _final_uri} <- fetch_with_redirects(url, opts),
         :ok <- validate_http_status(response, url),
         {:ok, content} <- Content.extract(final_url, response, opts),
         {:ok, result} <- Result.build(url, final_url, content, opts) do
      normalized_result = BrowserResult.normalize(result)
      Cache.store(url, opts, normalized_result)
      {:ok, normalized_result}
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
    |> Content.response_header("location")
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
      {:ok, Keyword.update(status_opts, :req, [], &remove_req_credentials/1)}
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

  defp finish_redirects(response, final_url) do
    final_uri = final_url |> URI.parse() |> URLRules.normalize_uri()
    final_url = URI.to_string(final_uri)
    {:ok, Map.put(response, :final_url, final_url), final_url, final_uri}
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
end
