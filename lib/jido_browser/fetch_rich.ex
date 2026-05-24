defmodule Jido.Browser.FetchRich do
  @moduledoc """
  HTTP-first retrieval with optional browser fallback for agent workflows.

  This module keeps `Jido.Browser.web_fetch/2` stateless and adds a small
  strategy layer for callers that want a single rich retrieval entrypoint.
  """

  alias Jido.Browser.Error

  @http_option_keys [
    :allowed_domains,
    :backend,
    :blocked_domains,
    :browsey,
    :cache,
    :cache_ttl_ms,
    :citations,
    :extractous,
    :focus_terms,
    :focus_window,
    :format,
    :known_urls,
    :max_content_tokens,
    :max_redirects,
    :max_url_length,
    :req,
    :require_known_url,
    :selector,
    :timeout
  ]

  @browser_start_keys [:adapter, :checkout_timeout, :headless, :pool, :timeout]

  @blocked_markers [
    "access denied",
    "are you a human",
    "captcha",
    "checking your browser",
    "cloudflare",
    "enable javascript",
    "just a moment",
    "rate limit",
    "too many requests",
    "unusual traffic",
    "verify you are human"
  ]

  @doc """
  Fetches a URL with HTTP-first retrieval and optional browser fallback.
  """
  @spec fetch(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def fetch(url, opts) when is_binary(url) and is_list(opts) do
    url
    |> fetch_http(opts)
    |> handle_fetch_result(url, opts)
  end

  defp fetch_http(url, opts) do
    fetch_http(url, opts, http_backends(opts), nil)
  end

  defp fetch_http(_url, _opts, [], {:blocked, result, reason}), do: {:blocked, result, reason}
  defp fetch_http(_url, _opts, [], {:error, reason}), do: {:error, reason}

  defp fetch_http(url, opts, [backend | rest], last_result) do
    web_opts = opts |> Keyword.take(@http_option_keys) |> put_backend(backend)
    retrieval_path = http_retrieval_path(backend, web_opts)

    case Jido.Browser.web_fetch(url, web_opts) do
      {:ok, result} -> handle_http_success(result, retrieval_path, url, opts, rest)
      {:error, reason} -> handle_http_error(reason, last_result, url, opts, rest)
    end
  end

  defp handle_fetch_result({:ok, result}, _url, _opts), do: {:ok, result}

  defp handle_fetch_result({:blocked, result, reason}, url, opts) do
    maybe_browser_fallback(url, opts, reason, fn -> {:ok, result} end)
  end

  defp handle_fetch_result({:error, reason}, url, opts) do
    if fallback_error?(reason) do
      maybe_browser_fallback(url, opts, fallback_reason(reason), fn -> {:error, reason} end)
    else
      {:error, reason}
    end
  end

  defp handle_http_success(result, retrieval_path, url, opts, rest) do
    case blocked_reason(result) do
      nil ->
        {:ok, tag_result(result, retrieval_path, nil, false)}

      reason ->
        fetch_http(url, opts, rest, {:blocked, tag_result(result, retrieval_path, reason, true), reason})
    end
  end

  defp handle_http_error(reason, last_result, url, opts, rest) do
    cond do
      rest != [] and fallback_error?(reason) ->
        fetch_http(url, opts, rest, {:error, reason})

      match?({:blocked, _result, _blocked_reason}, last_result) ->
        last_result

      true ->
        {:error, reason}
    end
  end

  defp maybe_browser_fallback(url, opts, reason, fallback_fun) do
    if browser_fallback?(opts) do
      fetch_browser(url, opts, reason)
    else
      fallback_fun.()
    end
  end

  defp fetch_browser(url, opts, fallback_reason) do
    case Jido.Browser.start_session(browser_start_opts(opts)) do
      {:ok, session} ->
        try do
          with {:ok, session, nav_result} <- Jido.Browser.navigate(session, url, timeout: opts[:timeout]),
               {:ok, result} <- browser_result(session, nav_result, url, opts, fallback_reason) do
            {:ok, result}
          else
            {:error, reason} ->
              {:error,
               Error.adapter_error("Browser fallback failed", %{
                 reason: reason,
                 fallback_reason: fallback_reason,
                 url: url
               })}
          end
        after
          _ = Jido.Browser.end_session(session)
        end

      {:error, reason} ->
        {:error,
         Error.adapter_error("Browser fallback failed to start", %{
           reason: reason,
           fallback_reason: fallback_reason,
           url: url
         })}
    end
  end

  defp browser_result(session, nav_result, url, opts, fallback_reason) do
    with {:ok, attrs} <- browser_attrs(session, nav_result, url, opts) do
      result = build_browser_result(attrs, opts, fallback_reason)
      {:ok, result}
    end
  end

  defp browser_attrs(session, nav_result, url, opts) do
    if opts[:format] == :html do
      extract_attrs(session, nav_result, url, opts)
    else
      snapshot_attrs(session, nav_result, url, opts)
    end
  end

  defp snapshot_attrs(session, nav_result, url, opts) do
    snapshot_opts =
      opts
      |> Keyword.take([:selector, :timeout])
      |> Keyword.put_new(:selector, "body")
      |> Keyword.put_new(:max_content_length, max_content_length(opts))

    case Jido.Browser.snapshot(session, snapshot_opts) do
      {:ok, _session, snapshot} when is_map(snapshot) ->
        content = snapshot_content(snapshot)

        if empty_content?(content) do
          extract_attrs(session, nav_result, url, opts)
        else
          {:ok,
           %{
             content: content,
             final_url: result_value(snapshot, :url) || result_value(nav_result, :url) || url,
             title: result_value(snapshot, :title),
             format: :markdown
           }}
        end

      {:error, _reason} ->
        extract_attrs(session, nav_result, url, opts)
    end
  end

  defp extract_attrs(session, nav_result, url, opts) do
    extract_opts =
      opts
      |> Keyword.take([:format, :selector, :timeout])
      |> Keyword.put_new(:format, :markdown)
      |> Keyword.put_new(:selector, "body")

    with {:ok, _session, result} <- Jido.Browser.extract_content(session, extract_opts) do
      {:ok,
       %{
         content: result_value(result, :content) || "",
         final_url: result_value(nav_result, :url) || url,
         title: result_value(result, :title),
         format: result_value(result, :format) || extract_opts[:format]
       }}
    end
  end

  defp build_browser_result(attrs, opts, fallback_reason) do
    content = attrs.content || ""
    {content, truncated, original_estimated_tokens} = maybe_truncate(content, opts[:max_content_tokens])
    blocked_reason = blocked_reason(%{content: content})
    blocked? = not is_nil(blocked_reason)

    %{
      url: attrs.final_url,
      final_url: attrs.final_url,
      title: attrs.title,
      content: content,
      format: attrs.format,
      content_type: "text/html",
      document_type: :html,
      retrieved_at: retrieved_at(),
      estimated_tokens: estimate_tokens(content),
      original_estimated_tokens: original_estimated_tokens,
      truncated: truncated,
      filtered: false,
      focus_matches: 0,
      cached: false,
      citations: %{enabled: citations_enabled?(opts)},
      passages: maybe_build_passages(content, attrs.title, attrs.final_url, citations_enabled?(opts)),
      retrieval_path: :browser,
      fallback_reason: fallback_reason,
      blocked?: blocked?
    }
  end

  defp tag_result(result, retrieval_path, fallback_reason, blocked?) do
    result
    |> Map.put(:retrieval_path, retrieval_path)
    |> Map.put(:fallback_reason, fallback_reason)
    |> Map.put(:blocked?, blocked?)
  end

  defp http_backends(opts) do
    case Keyword.get(opts, :http_backends) do
      nil ->
        [Keyword.get(opts, :backend, :default)]

      [] ->
        [Keyword.get(opts, :backend, :default)]

      backends ->
        List.wrap(backends)
    end
  end

  defp put_backend(opts, :default), do: Keyword.delete(opts, :backend)
  defp put_backend(opts, backend), do: Keyword.put(opts, :backend, backend)

  defp http_retrieval_path(:browsey, _opts), do: :browsey
  defp http_retrieval_path(Jido.Browser.WebFetch.Backends.Browsey, _opts), do: :browsey
  defp http_retrieval_path(_backend, opts), do: if(opts[:backend] == :browsey, do: :browsey, else: :web_fetch)

  defp browser_fallback?(opts), do: Keyword.get(opts, :browser_fallback, false) == true or Keyword.has_key?(opts, :pool)

  defp browser_start_opts(opts), do: Keyword.take(opts, @browser_start_keys)

  defp fallback_error?(%Error.AdapterError{details: details}) when is_map(details) do
    details[:status] in [401, 403, 429] or details[:error_code] in [:too_many_requests, :url_not_accessible]
  end

  defp fallback_error?(_reason), do: false

  defp fallback_reason(%Error.AdapterError{details: %{status: status}}) when status in [401, 403, 429] do
    {:http_status, status}
  end

  defp fallback_reason(%Error.AdapterError{details: %{error_code: error_code}}), do: error_code
  defp fallback_reason(reason), do: reason

  defp blocked_reason(result) when is_map(result) do
    content = result_value(result, :content) || ""
    downcased = String.downcase(content)

    cond do
      empty_content?(content) ->
        :empty_content

      Enum.any?(@blocked_markers, &String.contains?(downcased, &1)) ->
        :blocked_content

      true ->
        nil
    end
  end

  defp empty_content?(content) when is_binary(content), do: String.trim(content) == ""
  defp empty_content?(_content), do: true

  defp snapshot_content(snapshot) do
    result_value(snapshot, :snapshot) || result_value(snapshot, :content) || result_value(snapshot, :text) || ""
  end

  defp result_value(map, key) when is_map(map) and is_atom(key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp result_value(_map, _key), do: nil

  defp max_content_length(opts) do
    case opts[:max_content_tokens] do
      value when is_integer(value) and value > 0 -> value * 4
      _other -> 50_000
    end
  end

  defp maybe_truncate(content, max_content_tokens) when is_integer(max_content_tokens) and max_content_tokens > 0 do
    original_estimated_tokens = estimate_tokens(content)

    if original_estimated_tokens <= max_content_tokens do
      {content, false, original_estimated_tokens}
    else
      {content |> String.slice(0, max_content_tokens * 4) |> String.trim(), true, original_estimated_tokens}
    end
  end

  defp maybe_truncate(content, _max_content_tokens), do: {content, false, estimate_tokens(content)}

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

  defp citations_enabled?(opts), do: Keyword.get(opts, :citations, false) == true

  defp retrieved_at do
    DateTime.utc_now()
    |> DateTime.truncate(:second)
    |> DateTime.to_iso8601()
  end

  defp estimate_tokens(content) when is_binary(content), do: div(String.length(content) + 3, 4)
  defp estimate_tokens(_content), do: 0
end
