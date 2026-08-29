defimpl Zoi.JSONSchema.Encoder, for: Zoi.Types.Atom do
  @moduledoc false

  def encode(_schema), do: %{type: :string}
end
