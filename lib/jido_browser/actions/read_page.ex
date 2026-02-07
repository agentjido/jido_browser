defmodule JidoBrowser.Actions.ReadPage do
  @moduledoc """
  Self-contained action that reads a web page and returns its content.

  Manages the full browser session lifecycle internally (start, navigate,
  extract, close) so the caller doesn't need to track session state.

  ## Usage with Jido Agent

      tools: [JidoBrowser.Actions.ReadPage]

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
    vsn: "1.0.0",
    schema: [
      url: [type: :string, required: true, doc: "The URL to read"],
      selector: [type: :string, default: "body", doc: "CSS selector to scope extraction"],
      format: [
        type: {:in, [:markdown, :text, :html]},
        default: :markdown,
        doc: "Output format"
      ]
    ]

  @impl true
  def run(params, _context) do
    url = params.url
    selector = Map.get(params, :selector, "body")
    format = Map.get(params, :format, :markdown)

    case JidoBrowser.start_session(adapter: JidoBrowser.Adapters.Web) do
      {:ok, session} ->
        try do
          with {:ok, session, _nav_result} <- JidoBrowser.navigate(session, url),
               {:ok, _session, %{content: content}} <-
                 JidoBrowser.extract_content(session, selector: selector, format: format) do
            {:ok, %{url: url, content: content, format: format}}
          else
            {:error, reason} ->
              {:error, "Failed to read page #{url}: #{inspect(reason)}"}
          end
        after
          JidoBrowser.end_session(session)
        end

      {:error, reason} ->
        {:error, "Failed to start browser session: #{inspect(reason)}"}
    end
  end
end
