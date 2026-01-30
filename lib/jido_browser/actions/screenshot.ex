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
      format: [type: {:in, [:png]}, default: :png, doc: "Image format (only PNG is currently supported)"],
      save_path: [type: :string, doc: "Optional file path to save the screenshot"]
    ]

  alias JidoBrowser.ActionHelpers
  alias JidoBrowser.Error

  @impl true
  def run(params, context) do
    with {:ok, session} <- ActionHelpers.get_session(context) do
      opts = Keyword.new(params) |> Keyword.take([:full_page, :format])

      case JidoBrowser.screenshot(session, opts) do
        {:ok, updated_session, %{bytes: bytes, mime: mime}} ->
          result = build_result(bytes, mime, updated_session)
          result = maybe_save_file(result, bytes, params[:save_path])
          {:ok, result}

        {:error, reason} ->
          {:error, Error.adapter_error("Screenshot failed", %{reason: reason})}
      end
    end
  end

  defp build_result(bytes, mime, session) do
    %{
      status: "success",
      mime: mime,
      size: byte_size(bytes),
      base64: Base.encode64(bytes),
      session: session
    }
  end

  defp maybe_save_file(result, _bytes, nil), do: result

  defp maybe_save_file(result, bytes, save_path) do
    case File.write(save_path, bytes) do
      :ok -> Map.put(result, :saved_to, save_path)
      {:error, reason} -> Map.put(result, :save_error, inspect(reason))
    end
  end
end
