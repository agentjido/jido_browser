defmodule Jido.Browser.Actions.ExtractContent do
  @moduledoc """
  Jido Action for extracting page content.

  This is particularly useful for AI agents that need to read and understand
  web page content. The markdown format is optimized for LLM consumption.

  ## Usage with Jido Agent

      # In your agent's tool list
      tools: [Jido.Browser.Actions.ExtractContent]

      # The agent can then call:
      # extract_content()
      # extract_content(selector: "article.main")
      # extract_content(format: :html)
      # extract_content(format: :text)

  """

  use Jido.Action,
    name: "browser_extract_content",
    description: "Extract content from the current page as markdown, HTML, or text",
    category: "Browser",
    tags: ["browser", "content", "extract", "markdown", "web"],
    vsn: "2.0.0",
    schema: [
      selector: [type: :string, default: "body", doc: "CSS selector to scope extraction"],
      format: [type: {:in, [:markdown, :html, :text]}, default: :markdown, doc: "Output format"]
    ]

  alias Jido.Browser.ActionHelpers
  alias Jido.Browser.Error

  @impl true
  def run(params, context) do
    with {:ok, session} <- ActionHelpers.get_session(context) do
      opts = Keyword.new(params) |> Keyword.take([:selector, :format])

      case Jido.Browser.extract_content(session, opts) do
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
