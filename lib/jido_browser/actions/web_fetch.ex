defmodule Jido.Browser.Actions.WebFetch do
  @moduledoc """
  Stateless HTTP-first document retrieval for agent workflows.

  `WebFetch` is a lighter-weight alternative to browser navigation when the
  target content can be retrieved over plain HTTP(S) without JavaScript
  execution, including fetched PDFs and office-style documents.
  """

  use Jido.Browser.Action,
    name: "web_fetch",
    description:
      "Fetch a URL over HTTP(S) with domain policy controls, optional Extractous-backed document extraction, " <>
        "optional focused filtering, approximate token caps, and citation-ready passages.",
    schema:
      Zoi.object(%{
        url: Zoi.string(description: "The URL to fetch"),
        format:
          Zoi.enum([:markdown, :text, :html], description: "Output format")
          |> Zoi.default(:markdown)
          |> Zoi.optional(),
        backend: Zoi.enum([:req], description: "Req HTTP backend") |> Zoi.optional(),
        selector: Zoi.string(description: "Optional CSS selector for HTML pages") |> Zoi.optional(),
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
          Zoi.list(Zoi.string(), description: "Terms used to filter the fetched document")
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
        timeout: Zoi.integer(description: "Receive timeout in milliseconds") |> Zoi.optional(),
        require_known_url:
          Zoi.boolean(description: "Require the URL to already be present in tool context")
          |> Zoi.default(false)
          |> Zoi.optional(),
        known_urls:
          Zoi.list(Zoi.string(), description: "Additional known URLs accepted for provenance checks")
          |> Zoi.default([])
          |> Zoi.optional(),
        max_uses:
          Zoi.integer(description: "Maximum successful web fetch calls allowed in current skill state")
          |> Zoi.optional()
      }),
    output_schema:
      Zoi.object(%{
        status: Zoi.literal("success"),
        url: Zoi.string(),
        final_url: Zoi.string(),
        title: Zoi.string() |> Zoi.nullish(),
        content: Zoi.string(),
        format: Zoi.enum([:markdown, :text, :html]),
        content_type: Zoi.string(),
        document_type: Zoi.atom(),
        retrieved_at: Zoi.string(),
        estimated_tokens: Zoi.integer(gte: 0),
        original_estimated_tokens: Zoi.integer(gte: 0),
        truncated: Zoi.boolean(),
        filtered: Zoi.boolean(),
        focus_matches: Zoi.integer(gte: 0),
        cached: Zoi.boolean(),
        citations: Zoi.map(),
        passages: Zoi.list(Zoi.map()),
        metadata: Zoi.map() |> Zoi.optional()
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
         {:ok, result} <- Jido.Browser.web_fetch(params.url, build_opts(params, context)) do
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
    |> maybe_put(:timeout, params[:timeout])
    |> maybe_put(:require_known_url, Map.get(params, :require_known_url, false))
    |> maybe_put(:known_urls, known_urls)
  end

  defp validate_max_uses(%{max_uses: max_uses}, context) when is_integer(max_uses) and max_uses >= 0 do
    current_uses = get_in(context, [:skill_state, :web_fetch_uses]) || 0

    if current_uses >= max_uses do
      {:error,
       Error.invalid_error("Web fetch max uses exceeded", %{
         error_code: :max_uses_exceeded,
         max_uses: max_uses,
         current_uses: current_uses
       })}
    else
      :ok
    end
  end

  defp validate_max_uses(_params, _context), do: :ok

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
