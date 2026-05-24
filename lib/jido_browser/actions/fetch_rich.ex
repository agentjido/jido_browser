defmodule Jido.Browser.Actions.FetchRich do
  @moduledoc """
  Agent-oriented URL retrieval with HTTP-first fetching and optional browser fallback.
  """

  use Jido.Action,
    name: "fetch_rich",
    description:
      "Fetch a URL with normalized rich content, using fast HTTP retrieval first and optional browser fallback.",
    category: "Browser",
    tags: ["browser", "web", "fetch", "retrieval", "agent"],
    vsn: "2.0.0",
    schema: [
      url: [type: :string, required: true, doc: "The URL to fetch"],
      format: [type: {:in, [:markdown, :text, :html]}, default: :markdown, doc: "Output format"],
      backend: [type: {:in, [:req, :browsey]}, doc: "Preferred HTTP backend"],
      http_backends: [type: {:list, :atom}, doc: "HTTP backend sequence, such as [:req, :browsey]"],
      selector: [type: :string, doc: "Optional CSS selector for HTML/browser extraction"],
      allowed_domains: [type: {:list, :string}, default: [], doc: "Allow-list of host or host/path rules"],
      blocked_domains: [type: {:list, :string}, default: [], doc: "Block-list of host or host/path rules"],
      focus_terms: [type: {:list, :string}, default: [], doc: "Terms used to filter fetched documents"],
      focus_window: [type: :integer, default: 0, doc: "Paragraph window around each focus match"],
      max_content_tokens: [type: :integer, doc: "Approximate token cap for returned content"],
      citations: [type: :boolean, default: false, doc: "Include citation-ready passage offsets"],
      cache: [type: :boolean, default: true, doc: "Reuse cached fetch results when available"],
      timeout: [type: :integer, doc: "Timeout in milliseconds"],
      browser_fallback: [type: :boolean, default: false, doc: "Allow fallback to a browser session"],
      pool: [type: :any, doc: "Optional warm browser pool used for browser fallback"],
      checkout_timeout: [type: :integer, doc: "Warm pool checkout timeout in ms"],
      adapter: [type: :atom, doc: "Browser adapter module for fallback"],
      headless: [type: :boolean, doc: "Run fallback browser headless"],
      require_known_url: [type: :boolean, default: false, doc: "Require the URL to be present in context"],
      known_urls: [type: {:list, :string}, default: [], doc: "Additional known URLs accepted for provenance"],
      max_uses: [type: :integer, doc: "Maximum successful rich fetch calls allowed in current skill state"]
    ]

  alias Jido.Browser.Error

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
    |> maybe_put(:focus_terms, Map.get(params, :focus_terms, []))
    |> maybe_put(:focus_window, Map.get(params, :focus_window, 0))
    |> maybe_put(:max_content_tokens, params[:max_content_tokens])
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
end
