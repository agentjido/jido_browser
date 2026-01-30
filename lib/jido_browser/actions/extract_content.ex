defmodule JidoBrowser.Actions.ExtractContent do
  @moduledoc """
  Jido Action for extracting page content.

  This is particularly useful for AI agents that need to read and understand
  web page content. The markdown format is optimized for LLM consumption.

  ## Usage with Jido Agent

      # In your agent's tool list
      tools: [JidoBrowser.Actions.ExtractContent]

      # The agent can then call:
      # extract_content()
      # extract_content(selector: "article.main")
      # extract_content(format: :html)

  """

  use Jido.Action,
    name: "browser_extract_content",
    description: "Extract content from the current page as markdown or HTML",
    category: "Browser",
    tags: ["browser", "content", "extract", "markdown", "web"],
    vsn: "1.0.0",
    schema: [
      selector: [type: :string, default: "body", doc: "CSS selector to scope extraction"],
      format: [type: {:in, [:markdown, :html]}, default: :markdown, doc: "Output format"]
    ]

  alias JidoBrowser.ActionHelpers
  alias JidoBrowser.Error

  @impl true
  def run(params, context) do
    with {:ok, session} <- ActionHelpers.get_session(context) do
      opts = Keyword.new(params) |> Keyword.take([:selector, :format])

      case JidoBrowser.extract_content(session, opts) do
        {:ok, updated_session, %{content: content, format: format}} ->
          {:ok,
           %{
             status: "success",
             content: content,
             format: format,
             length: String.length(content),
             session: updated_session
           }}

        {:error, reason} ->
          {:error, Error.adapter_error("Extract content failed", %{reason: reason})}
      end
    end
  end
end
