defmodule Jido.Browser.Actions.ReadPage do
  @moduledoc """
  Self-contained action that reads a web page and returns its content.

  Manages the full browser session lifecycle internally (start, navigate,
  extract, close) so the caller doesn't need to track session state.

  ## Usage with Jido Agent

      tools: [Jido.Browser.Actions.ReadPage]

      # The agent can then call:
      # read_page(url: "https://example.com")
      # read_page(url: "https://example.com", selector: "article", format: :html)

  """

  use Jido.Action,
    name: "read_page",
    description:
      "Read a web page and return its content as markdown, text, or HTML. " <>
        "Manages browser session automatically.",
    category: "Browser",
    tags: ["browser", "web", "read", "content", "markdown"],
    vsn: "2.0.0",
    schema: [
      url: [type: :string, required: true, doc: "The URL to read"],
      selector: [type: :string, default: "body", doc: "CSS selector to scope extraction"],
      format: [
        type: {:in, [:markdown, :text, :html]},
        default: :markdown,
        doc: "Output format"
      ],
      pool: [type: :any, doc: "Optional warm session pool name"],
      checkout_timeout: [type: :integer, doc: "Warm pool checkout timeout in ms"],
      adapter: [type: :atom, doc: "Browser adapter module"],
      headless: [type: :boolean, doc: "Run in headless mode"],
      timeout: [type: :integer, doc: "Default browser timeout in ms"]
    ]

  @impl true
  def run(params, context) do
    url = params.url
    selector = Map.get(params, :selector, "body")
    format = Map.get(params, :format, :markdown)
    start_opts = session_start_opts(params, context)

    case Jido.Browser.start_session(start_opts) do
      {:ok, session} ->
        try do
          with {:ok, session, _nav_result} <- Jido.Browser.navigate(session, url),
               {:ok, _session, %{content: content}} <-
                 Jido.Browser.extract_content(session, selector: selector, format: format) do
            {:ok, %{url: url, content: content, format: format}}
          else
            {:error, reason} ->
              {:error, "Failed to read page #{url}: #{inspect(reason)}"}
          end
        after
          Jido.Browser.end_session(session)
        end

      {:error, reason} ->
        {:error, "Failed to start browser session: #{inspect(reason)}"}
    end
  end

  defp session_start_opts(params, context) do
    []
    |> maybe_put(:adapter, session_option(params, context, :adapter))
    |> maybe_put(:headless, session_option(params, context, :headless))
    |> maybe_put(:timeout, session_option(params, context, :timeout))
    |> maybe_put(:pool, session_option(params, context, :pool))
    |> maybe_put(:checkout_timeout, session_option(params, context, :checkout_timeout))
  end

  defp session_option(params, context, key) do
    case Map.fetch(params, key) do
      {:ok, nil} -> get_in(context, [:skill_state, key])
      {:ok, value} -> value
      :error -> get_in(context, [:skill_state, key])
    end
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
end
