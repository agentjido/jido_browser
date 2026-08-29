defmodule Jido.Browser.ID do
  @moduledoc false

  @type t :: String.t()

  @doc false
  @spec generate() :: t()
  def generate, do: Jido.generate_id()
end
