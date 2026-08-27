defmodule Jido.Browser.TestSupport.WebFetchResolver do
  @moduledoc false

  @doc false
  @spec resolve(String.t()) :: {:ok, [:inet.ip_address()]}
  def resolve(_host), do: {:ok, [{93, 184, 216, 34}]}
end
