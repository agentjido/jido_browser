defmodule Jido.Browser.ActionHelpers do
  @moduledoc """
  Shared helper functions for Jido.Browser action modules.

  Provides common utilities like session extraction with proper error handling
  (returning `{:error, reason}` tuples instead of raising).
  """

  alias Jido.Browser.Error
  alias Jido.Browser.Result

  @doc """
  Extracts the browser session from the action context.

  Looks for the session in these locations (in order):
  - `context[:session]`
  - `context[:browser_session]`
  - `context[:tool_context][:session]`

  Returns `{:ok, session}` if found, or `{:error, InvalidError}` if not.

  ## Examples

      iex> get_session(%{session: session})
      {:ok, session}

      iex> get_session(%{})
      {:error, %Jido.Browser.Error.InvalidError{message: "No browser session in context"}}

  """
  @spec get_session(map()) :: {:ok, Jido.Browser.Session.t()} | {:error, Error.InvalidError.t()}
  def get_session(context) do
    case find_session(context) do
      nil -> {:error, Error.invalid_error("No browser session in context", %{})}
      session -> {:ok, session}
    end
  end

  @doc """
  Fetches a value from a normalized result map.
  """
  @spec get_value(map(), atom()) :: term()
  def get_value(map, key) when is_map(map) and is_atom(key), do: Map.get(map, key)

  @doc """
  Unwraps a normalized adapter result nested under an atom `:result` key.
  """
  @spec unwrap_result(map()) :: map()
  def unwrap_result(map) when is_map(map) do
    case Map.get(map, :result) do
      nested when is_map(nested) -> Result.normalize(nested)
      _ -> map
    end
  end

  defp find_session(context) do
    context[:session] ||
      context[:browser_session] ||
      get_in(context, [:tool_context, :session])
  end
end
