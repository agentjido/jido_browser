defmodule Jido.Browser.Schema do
  @moduledoc false

  @spec atom_enum([atom()], keyword()) :: Zoi.schema()
  def atom_enum(values, opts \\ []) do
    mapping = Enum.map(values, &{&1, Atom.to_string(&1)})
    Zoi.enum(mapping, Keyword.put(opts, :coerce, true))
  end
end
