defmodule JidoBrowser.Actions.Screenshot do
  @moduledoc """
  Jido Action for taking a screenshot.

  ## Usage with Jido Agent

      # In your agent's tool list
      tools: [JidoBrowser.Actions.Screenshot]

      # The agent can then call:
      # screenshot()
      # screenshot(full_page: true)

  """

  use Jido.Action,
    name: "browser_screenshot",
    description: "Take a screenshot of the current page",
    category: "Browser",
    tags: ["browser", "screenshot", "capture", "web"],
    vsn: "1.0.0",
    schema: [
      full_page: [type: :boolean, default: false, doc: "Capture the full scrollable page"],
      format: [type: {:in, [:png, :jpeg]}, default: :png, doc: "Image format"],
      save_path: [type: :string, doc: "Optional file path to save the screenshot"]
    ]

  alias JidoBrowser.Error

  @impl true
  def run(params, context) do
    session = get_session(context)
    opts = Keyword.new(params) |> Keyword.take([:full_page, :format])

    case JidoBrowser.screenshot(session, opts) do
      {:ok, %{bytes: bytes, mime: mime}} ->
        result = %{
          status: "success",
          mime: mime,
          size: byte_size(bytes),
          base64: Base.encode64(bytes)
        }

        # Optionally save to file
        result =
          if params[:save_path] do
            case File.write(params[:save_path], bytes) do
              :ok -> Map.put(result, :saved_to, params[:save_path])
              {:error, reason} -> Map.put(result, :save_error, inspect(reason))
            end
          else
            result
          end

        {:ok, result}

      {:error, reason} ->
        {:error, Error.adapter_error("Screenshot failed", %{reason: reason})}
    end
  end

  defp get_session(context) do
    context[:session] ||
      context[:browser_session] ||
      get_in(context, [:tool_context, :session]) ||
      raise "No browser session in context"
  end
end
