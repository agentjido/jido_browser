defmodule Jido.Browser.WebFetch.DocumentExtractor do
  @moduledoc false

  @doc false
  @spec extract(binary(), keyword()) :: {:ok, map()} | {:error, term()}
  def extract(bytes, opts) do
    ExtractousEx.extract_from_bytes(bytes, opts)
  end
end
