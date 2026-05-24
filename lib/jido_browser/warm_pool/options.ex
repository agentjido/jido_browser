defmodule Jido.Browser.WarmPool.Options do
  @moduledoc false

  alias Jido.Browser.Error

  @lifecycles [:ephemeral, :persistent]

  @doc false
  @spec normalize(keyword()) :: {:ok, keyword()} | {:error, Error.InvalidError.t()}
  def normalize(opts) do
    with {:ok, lifecycle} <- normalize_lifecycle(Keyword.get(opts, :lifecycle, :ephemeral)),
         {:ok, max_uses} <- normalize_optional_positive_integer(:max_uses, Keyword.get(opts, :max_uses)),
         {:ok, max_age_ms} <- normalize_optional_positive_integer(:max_age_ms, Keyword.get(opts, :max_age_ms)) do
      {:ok,
       []
       |> Keyword.put(:lifecycle, lifecycle)
       |> maybe_put(:max_uses, max_uses)
       |> maybe_put(:max_age_ms, max_age_ms)}
    end
  end

  defp normalize_lifecycle(lifecycle) when lifecycle in @lifecycles, do: {:ok, lifecycle}

  defp normalize_lifecycle(lifecycle) do
    {:error,
     Error.invalid_error("Pool lifecycle must be :ephemeral or :persistent", %{
       lifecycle: lifecycle,
       supported_lifecycles: @lifecycles
     })}
  end

  defp normalize_optional_positive_integer(_key, nil), do: {:ok, nil}
  defp normalize_optional_positive_integer(_key, value) when is_integer(value) and value > 0, do: {:ok, value}

  defp normalize_optional_positive_integer(key, value) do
    {:error,
     Error.invalid_error("#{key} must be a positive integer", %{
       option: key,
       value: value
     })}
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
end
