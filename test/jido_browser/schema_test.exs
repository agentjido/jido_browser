defmodule Jido.Browser.SchemaTest do
  use ExUnit.Case, async: true

  alias Jido.Browser.Schema

  test "atom enums retain native values and export JSON strings" do
    schema = Schema.atom_enum([:up, :down])

    assert %{type: :string, enum: ["up", "down"]} = Zoi.to_json_schema(schema)
    assert {:ok, :up} = Zoi.parse(schema, :up)
    assert {:ok, :up} = Zoi.parse(schema, "up")
    assert {:error, _} = Zoi.parse(schema, :left)
    assert {:error, _} = Zoi.parse(schema, "left")
  end

  test "enum defaults and descriptions remain in the exported schema" do
    schema = Schema.atom_enum([:visible, :hidden], description: "Selector state") |> Zoi.default(:visible)

    assert %{type: :string, default: :visible, description: "Selector state"} = Zoi.to_json_schema(schema)
    assert {:ok, :visible} = Zoi.parse(schema, nil)
  end
end
