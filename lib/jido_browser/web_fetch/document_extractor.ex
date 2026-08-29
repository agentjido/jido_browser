defmodule Jido.Browser.WebFetch.DocumentExtractor do
  @moduledoc false

  @extractor ExtractousEx

  @compile {:no_warn_undefined, @extractor}

  @doc false
  @spec available?() :: boolean()
  def available? do
    Code.ensure_loaded?(@extractor) and function_exported?(@extractor, :extract_from_bytes, 2)
  end

  @doc false
  @spec extract(binary(), keyword()) :: {:ok, map()} | {:error, term()}
  def extract(bytes, opts) do
    if available?() do
      ExtractousEx.extract_from_bytes(bytes, opts)
    else
      {:error, :dependency_unavailable}
    end
  end
end
