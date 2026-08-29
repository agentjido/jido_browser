defmodule Jido.Browser.Actions.Type do
  @moduledoc """
  Jido Action for typing text into an element.

  ## Usage with Jido Agent

      # In your agent's tool list
      tools: [Jido.Browser.Actions.Type]

      # The agent can then call:
      # type(selector: "input#email", text: "user@example.com")

  """

  use Jido.Browser.Action,
    name: "browser_type",
    description: "Type text into an element in the browser",
    schema:
      Zoi.object(%{
        selector: Zoi.string(description: "CSS selector for the input element"),
        text: Zoi.string(description: "Text to type into the element"),
        clear:
          Zoi.boolean(description: "Clear the field before typing")
          |> Zoi.default(false)
          |> Zoi.optional(),
        timeout: Zoi.integer(description: "Timeout in milliseconds") |> Zoi.optional()
      })

  alias Jido.Browser.ActionHelpers
  alias Jido.Browser.Error

  @impl true
  def run(params, context) do
    with {:ok, session} <- ActionHelpers.get_session(context) do
      opts = Keyword.new(params) |> Keyword.take([:clear, :timeout])

      case Jido.Browser.type(session, params.selector, params.text, opts) do
        {:ok, updated_session, result} ->
          {:ok, %{status: "success", selector: params.selector, result: result, session: updated_session}}

        {:error, %Error.ElementError{} = error} ->
          {:error, error}

        {:error, reason} ->
          {:error, Error.element_error("type", params.selector, reason)}
      end
    end
  end
end
