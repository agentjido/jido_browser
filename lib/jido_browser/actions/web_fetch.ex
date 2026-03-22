defmodule Jido.Browser.Actions.WebFetch do
  @moduledoc """
  Stateless HTTP-first page retrieval for agent workflows.

  `WebFetch` is a lighter-weight alternative to browser navigation when the
  target content can be retrieved over plain HTTP(S) without JavaScript
  execution.
  """

  use Jido.Action,
    name: "web_fetch",
    description:
      "Fetch a URL over HTTP(S) with domain policy controls, optional focused filtering, " <>
        "approximate token caps, and citation-ready passages.",
    category: "Browser",
    tags: ["browser", "web", "fetch", "http", "retrieval"],
    vsn: "2.0.0",
    schema: [
      url: [type: :string, required: true, doc: "The URL to fetch"],
      format: [type: {:in, [:markdown, :text, :html]}, default: :markdown, doc: "Output format"],
      selector: [type: :string, doc: "Optional CSS selector for HTML pages"],
      allowed_domains: [type: {:list, :string}, default: [], doc: "Allow-list of host or host/path rules"],
      blocked_domains: [type: {:list, :string}, default: [], doc: "Block-list of host or host/path rules"],
      focus_terms: [type: {:list, :string}, default: [], doc: "Terms used to filter the fetched document"],
      focus_window: [type: :integer, default: 0, doc: "Paragraph window around each focus match"],
      max_content_tokens: [type: :integer, doc: "Approximate token cap for returned content"],
      citations: [type: :boolean, default: false, doc: "Include citation-ready passage offsets"],
      cache: [type: :boolean, default: true, doc: "Reuse cached fetch results when available"],
      timeout: [type: :integer, doc: "Receive timeout in milliseconds"],
      require_known_url: [type: :boolean, default: false, doc: "Require the URL to already be present in tool context"],
      known_urls: [type: {:list, :string}, default: [], doc: "Additional known URLs accepted for provenance checks"],
      max_uses: [type: :integer, doc: "Maximum successful web fetch calls allowed in current skill state"]
    ]

  alias Jido.Browser.Error

  @impl true
  def run(params, context) do
    with :ok <- validate_max_uses(params, context),
         {:ok, result} <- Jido.Browser.web_fetch(params.url, build_opts(params, context)) do
      {:ok, Map.put(result, :status, "success")}
    else
      {:error, %_{} = error} ->
        {:error, error}

      {:error, reason} ->
        {:error, Error.adapter_error("Web fetch failed", %{reason: reason})}
    end
  end

  defp build_opts(params, context) do
    known_urls =
      (Map.get(params, :known_urls, []) || [])
      |> Kernel.++(get_in(context, [:skill_state, :seen_urls]) || [])
      |> Enum.uniq()

    []
    |> maybe_put(:format, Map.get(params, :format, :markdown))
    |> maybe_put(:selector, params[:selector])
    |> maybe_put(:allowed_domains, Map.get(params, :allowed_domains, []))
    |> maybe_put(:blocked_domains, Map.get(params, :blocked_domains, []))
    |> maybe_put(:focus_terms, Map.get(params, :focus_terms, []))
    |> maybe_put(:focus_window, Map.get(params, :focus_window, 0))
    |> maybe_put(:max_content_tokens, params[:max_content_tokens])
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
end
