defmodule Jido.Browser.WebFetch.Options do
  @moduledoc false

  alias Jido.Browser.Error

  @default_backend Jido.Browser.WebFetch.Backends.Req
  @default_timeout 15_000
  @default_req_max_redirects 10
  @default_max_response_bytes 5 * 1024 * 1024
  @default_cache_ttl_ms 300_000
  @supported_formats [:markdown, :text, :html]

  @doc false
  @spec normalize(keyword()) :: {:ok, keyword()} | {:error, Exception.t()}
  def normalize(opts) do
    format = opts[:format] || :markdown
    citations = normalize_citations(opts[:citations])
    focus_terms = normalize_focus_terms(opts[:focus_terms])

    with {:ok, backend} <- normalize_backend(Keyword.get(opts, :backend, config(:backend, @default_backend))),
         {:ok, configured_req_opts} <- normalize_backend_opts(:req, config(:req, [])),
         {:ok, request_req_opts} <- normalize_backend_opts(:req, Keyword.get(opts, :req, [])),
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
         {:ok, max_response_bytes} <-
           normalize_max_response_bytes(
             Keyword.get(opts, :max_response_bytes, config(:max_response_bytes, @default_max_response_bytes))
           ),
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
            |> Keyword.put(:max_response_bytes, max_response_bytes)
            |> Keyword.put(:require_known_url, require_known_url)
            |> Keyword.put(:extractous, merge_extractous_opts(configured_extractous_opts, request_extractous_opts))
            |> maybe_put(:max_content_tokens, max_content_tokens)
            |> maybe_put(:max_url_length, max_url_length)
            |> Keyword.put_new(:known_urls, [])

          {:ok, normalized}
      end
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

  defp backend_redirect_limit(_backend, req_opts) do
    Keyword.get(req_opts, :max_redirects, @default_req_max_redirects)
  end

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
     Error.invalid_error("Web fetch backend must be :req or a backend module", %{
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

  defp normalize_max_response_bytes(:infinity), do: {:ok, :infinity}

  defp normalize_max_response_bytes(value) when is_integer(value) and value > 0,
    do: {:ok, value}

  defp normalize_max_response_bytes(value) do
    {:error,
     Error.invalid_error("max_response_bytes must be a positive integer or :infinity", %{
       error_code: :invalid_input,
       option: :max_response_bytes,
       value: value
     })}
  end

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

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp config(key, default) do
    :jido_browser
    |> Application.get_env(:web_fetch, [])
    |> Keyword.get(key, default)
  end
end
