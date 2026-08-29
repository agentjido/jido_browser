defmodule Jido.Browser.Actions.FetchRich do
  @moduledoc """
  Agent-oriented URL retrieval with HTTP-first fetching and optional browser fallback.
  """

  use Jido.Browser.Action,
    name: "fetch_rich",
    description:
      "Fetch a URL with normalized rich content, using fast HTTP retrieval first and optional browser fallback.",
    schema:
      Zoi.object(%{
        url: Zoi.string(description: "The URL to fetch"),
        format:
          Zoi.enum([:markdown, :text, :html], description: "Output format")
          |> Zoi.default(:markdown)
          |> Zoi.optional(),
        backend: Zoi.enum([:req], description: "Preferred Req HTTP backend") |> Zoi.optional(),
        http_backends:
          Zoi.list(Zoi.atom(), description: "HTTP backend sequence, such as [:req]")
          |> Zoi.optional(),
        selector: Zoi.string(description: "Optional CSS selector for HTML/browser extraction") |> Zoi.optional(),
        allowed_domains:
          Zoi.list(Zoi.string(), description: "Allow-list of host or host/path rules")
          |> Zoi.default([])
          |> Zoi.optional(),
        blocked_domains:
          Zoi.list(Zoi.string(), description: "Block-list of host or host/path rules")
          |> Zoi.default([])
          |> Zoi.optional(),
        allow_private_network:
          Zoi.boolean(description: "Allow private network destinations")
          |> Zoi.default(false)
          |> Zoi.optional(),
        focus_terms:
          Zoi.list(Zoi.string(), description: "Terms used to filter fetched documents")
          |> Zoi.default([])
          |> Zoi.optional(),
        focus_window:
          Zoi.integer(description: "Paragraph window around each focus match")
          |> Zoi.default(0)
          |> Zoi.optional(),
        max_content_tokens: Zoi.integer(description: "Approximate token cap for returned content") |> Zoi.optional(),
        max_response_bytes:
          Zoi.union([Zoi.integer() |> Zoi.min(0), Zoi.literal(:infinity)],
            description: "Positive response byte cap, or infinity to disable the cap"
          )
          |> Zoi.default(5 * 1024 * 1024)
          |> Zoi.optional(),
        citations:
          Zoi.boolean(description: "Include citation-ready passage offsets")
          |> Zoi.default(false)
          |> Zoi.optional(),
        cache:
          Zoi.boolean(description: "Reuse cached fetch results when available")
          |> Zoi.default(true)
          |> Zoi.optional(),
        timeout: Zoi.integer(description: "Timeout in milliseconds") |> Zoi.optional(),
        browser_fallback:
          Zoi.boolean(description: "Allow fallback to a browser session")
          |> Zoi.default(false)
          |> Zoi.optional(),
        pool: Zoi.any(description: "Optional warm browser pool used for browser fallback") |> Zoi.optional(),
        checkout_timeout: Zoi.integer(description: "Warm pool checkout timeout in ms") |> Zoi.optional(),
        adapter: Zoi.atom(description: "Browser adapter module for fallback") |> Zoi.optional(),
        headless: Zoi.boolean(description: "Run fallback browser headless") |> Zoi.optional(),
        require_known_url:
          Zoi.boolean(description: "Require the URL to be present in context")
          |> Zoi.default(false)
          |> Zoi.optional(),
        known_urls:
          Zoi.list(Zoi.string(), description: "Additional known URLs accepted for provenance")
          |> Zoi.default([])
          |> Zoi.optional(),
        max_uses:
          Zoi.integer(description: "Maximum successful rich fetch calls allowed in current skill state")
          |> Zoi.optional()
      })

  alias Jido.Browser.Error

  @impl true
  def on_before_validate_params(params) when is_map(params) do
    params
    |> normalize_infinity()
    |> validate_response_limit()
  end

  @impl true
  def run(params, context) do
    with :ok <- validate_max_uses(params, context),
         {:ok, result} <- Jido.Browser.fetch_rich(params.url, build_opts(params, context)) do
      {:ok, Map.put(result, :status, "success")}
    else
      {:error, error} ->
        {:error, error}
    end
  end

  defp build_opts(params, context) do
    known_urls =
      (Map.get(params, :known_urls, []) || [])
      |> Kernel.++(get_in(context, [:skill_state, :seen_urls]) || [])
      |> Enum.uniq()

    []
    |> maybe_put(:format, Map.get(params, :format, :markdown))
    |> maybe_put(:backend, Map.get(params, :backend))
    |> maybe_put(:http_backends, Map.get(params, :http_backends))
    |> maybe_put(:selector, params[:selector])
    |> maybe_put(:allowed_domains, Map.get(params, :allowed_domains, []))
    |> maybe_put(:blocked_domains, Map.get(params, :blocked_domains, []))
    |> maybe_put(:allow_private_network, Map.get(params, :allow_private_network, false))
    |> maybe_put(:focus_terms, Map.get(params, :focus_terms, []))
    |> maybe_put(:focus_window, Map.get(params, :focus_window, 0))
    |> maybe_put(:max_content_tokens, params[:max_content_tokens])
    |> maybe_put(:max_response_bytes, Map.get(params, :max_response_bytes, 5 * 1024 * 1024))
    |> maybe_put(:citations, Map.get(params, :citations, false))
    |> maybe_put(:cache, Map.get(params, :cache, true))
    |> maybe_put(:timeout, session_option(params, context, :timeout))
    |> maybe_put(:browser_fallback, Map.get(params, :browser_fallback, false))
    |> maybe_put(:pool, session_option(params, context, :pool))
    |> maybe_put(:checkout_timeout, session_option(params, context, :checkout_timeout))
    |> maybe_put(:adapter, session_option(params, context, :adapter))
    |> maybe_put(:headless, session_option(params, context, :headless))
    |> maybe_put(:require_known_url, Map.get(params, :require_known_url, false))
    |> maybe_put(:known_urls, known_urls)
  end

  defp validate_max_uses(%{max_uses: max_uses}, context) when is_integer(max_uses) and max_uses >= 0 do
    current_uses = get_in(context, [:skill_state, :fetch_rich_uses]) || 0

    if current_uses >= max_uses do
      {:error,
       Error.invalid_error("Rich fetch max uses exceeded", %{
         error_code: :max_uses_exceeded,
         max_uses: max_uses,
         current_uses: current_uses
       })}
    else
      :ok
    end
  end

  defp validate_max_uses(_params, _context), do: :ok

  defp session_option(params, context, key) do
    case Map.fetch(params, key) do
      {:ok, nil} -> get_in(context, [:skill_state, key])
      {:ok, value} -> value
      :error -> get_in(context, [:skill_state, key])
    end
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, _key, []), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp normalize_infinity(%{max_response_bytes: "infinity"} = params) do
    %{params | max_response_bytes: :infinity}
  end

  defp normalize_infinity(params), do: params

  defp validate_response_limit(%{max_response_bytes: value}) when is_integer(value) and value <= 0 do
    {:error,
     Error.invalid_error("max_response_bytes must be a positive integer or :infinity", %{
       error_code: :invalid_input,
       option: :max_response_bytes,
       value: value
     })}
  end

  defp validate_response_limit(params), do: {:ok, params}
end
