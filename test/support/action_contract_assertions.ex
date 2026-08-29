defmodule Jido.Browser.ActionContractAssertions do
  @moduledoc false

  import ExUnit.Assertions

  @unknown_atom :contract_unknown_atom
  @unknown_string "contract_unknown_string"

  def assert_contract(%{module: action, name: name, description: description, schema: schema} = contract) do
    assert %Zoi.Types.Map{} = action.schema()

    assert_validation_contract(action, schema)
    assert_schema_metadata_contract(action, name, description, schema)

    case contract do
      %{output: output} -> assert_output_contract(action, output)
      _contract -> :ok
    end
  end

  defp assert_output_contract(action, output) do
    output_schema = action.output_schema()

    assert %Zoi.Types.Map{fields: fields} = output_schema
    refute schema_contains?(output_schema, &is_function/1)
    refute schema_contains?(output_schema, &match?(%Zoi.Types.Lazy{}, &1))

    assert fields |> Keyword.keys() |> MapSet.new() == MapSet.new(Map.keys(output))

    sample = Map.new(output, fn {key, type} -> {key, output_sample(type, key)} end)
    assert {:ok, ^sample} = action.validate_output(sample)

    output_with_unknown_keys =
      Map.merge(sample, %{@unknown_atom => :kept, @unknown_string => "kept"})

    assert {:ok, ^output_with_unknown_keys} = action.validate_output(output_with_unknown_keys)

    for {key, type} <- output do
      assert_output_presence(action, sample, key, type)
      assert_output_type(action, sample, key, type)
      assert_nullable_output(action, sample, key, type)
    end
  end

  defp assert_output_presence(action, sample, key, {:optional, _type}) do
    expected = Map.delete(sample, key)
    assert {:ok, ^expected} = action.validate_output(expected)
  end

  defp assert_output_presence(action, sample, key, _type) do
    assert {:error, _reason} = action.validate_output(Map.delete(sample, key))
  end

  defp assert_output_type(action, sample, key, type) do
    case invalid_output_value(type) do
      :unconstrained ->
        :ok

      invalid ->
        assert {:error, _reason} = action.validate_output(Map.put(sample, key, invalid))
    end
  end

  defp assert_nullable_output(action, sample, key, {:nullable, _type}) do
    expected = Map.put(sample, key, nil)
    assert {:ok, ^expected} = action.validate_output(expected)
  end

  defp assert_nullable_output(action, sample, key, {:optional, type}) do
    assert_nullable_output(action, sample, key, type)
  end

  defp assert_nullable_output(_action, _sample, _key, _type), do: :ok

  defp output_sample({:literal, value}, _key), do: value
  defp output_sample({:nullable, type}, key), do: output_sample(type, key)
  defp output_sample({:optional, type}, key), do: output_sample(type, key)
  defp output_sample({:list, type}, key), do: [output_sample(type, key)]
  defp output_sample({:in, [value | _values]}, _key), do: value
  defp output_sample(:string, key), do: "sample_#{key}"
  defp output_sample(:integer, _key), do: 7
  defp output_sample(:non_neg_integer, _key), do: 0
  defp output_sample(:boolean, _key), do: true
  defp output_sample(:atom, _key), do: :contract_sample
  defp output_sample(:map, _key), do: %{contract: "sample"}
  defp output_sample(:any, _key), do: {:contract, :sample}

  defp invalid_output_value({:literal, value}) when is_binary(value), do: value <> "_invalid"
  defp invalid_output_value({:literal, value}), do: {:not, value}
  defp invalid_output_value({:nullable, type}), do: invalid_output_value(type)
  defp invalid_output_value({:optional, type}), do: invalid_output_value(type)
  defp invalid_output_value({:list, _type}), do: %{}
  defp invalid_output_value({:in, _values}), do: :contract_invalid
  defp invalid_output_value(:string), do: 7
  defp invalid_output_value(:integer), do: "not-an-integer"
  defp invalid_output_value(:non_neg_integer), do: -1
  defp invalid_output_value(:boolean), do: "not-a-boolean"
  defp invalid_output_value(:atom), do: "not-an-atom"
  defp invalid_output_value(:map), do: []
  defp invalid_output_value(:any), do: :unconstrained

  defp schema_contains?(value, predicate) do
    predicate.(value) or schema_children_contain?(value, predicate)
  end

  defp schema_children_contain?(value, predicate) when is_map(value) do
    value
    |> Map.to_list()
    |> Enum.any?(fn {key, child} ->
      schema_contains?(key, predicate) or schema_contains?(child, predicate)
    end)
  end

  defp schema_children_contain?(value, predicate) when is_tuple(value) do
    value
    |> Tuple.to_list()
    |> Enum.any?(&schema_contains?(&1, predicate))
  end

  defp schema_children_contain?(value, predicate) when is_list(value) do
    Enum.any?(value, &schema_contains?(&1, predicate))
  end

  defp schema_children_contain?(_value, _predicate), do: false

  defp assert_validation_contract(action, schema) do
    all_atom_params = sample_params(schema)
    required_atom_params = required_params(schema)

    assert {:ok, ^all_atom_params} = action.validate_params(all_atom_params)

    expected_minimal_params = Map.merge(required_atom_params, default_params(schema))
    assert {:ok, ^expected_minimal_params} = action.validate_params(required_atom_params)

    params_with_unknown_keys =
      Map.merge(all_atom_params, %{@unknown_atom => :kept, @unknown_string => "kept"})

    assert {:ok, ^params_with_unknown_keys} = action.validate_params(params_with_unknown_keys)

    assert_direct_string_key_behavior(action, schema, required_atom_params)
  end

  defp assert_direct_string_key_behavior(action, schema, required_atom_params) do
    optional_string_params =
      schema
      |> Enum.reject(fn {_key, options} -> Map.get(options, :required, false) end)
      |> Map.new(fn {key, options} -> {Atom.to_string(key), sample_value(options.type, key)} end)

    mixed_params = Map.merge(required_atom_params, optional_string_params)

    expected_mixed_params =
      required_atom_params
      |> Map.merge(optional_string_params)
      |> Map.merge(default_params(schema))

    assert {:ok, ^expected_mixed_params} = action.validate_params(mixed_params)

    case required_atom_params do
      params when map_size(params) == 0 ->
        :ok

      params ->
        required_string_params = Map.new(params, fn {key, value} -> {Atom.to_string(key), value} end)

        assert {:error, %Jido.Action.Error.InvalidInputError{}} =
                 action.validate_params(required_string_params)
    end
  end

  defp assert_schema_metadata_contract(action, name, description, schema) do
    assert action.name() == name
    assert action.description() == description

    assert action.schema()
           |> Zoi.to_json_schema()
           |> normalize_json_schema() == expected_json_schema(schema)
  end

  defp expected_json_schema(schema) do
    properties =
      Map.new(schema, fn {key, options} ->
        property =
          options.type
          |> json_type()
          |> Map.put("description", options.doc)
          |> maybe_put_default(options)

        {Atom.to_string(key), property}
      end)

    required =
      schema
      |> Enum.filter(fn {_key, options} -> Map.get(options, :required, false) end)
      |> Enum.map(fn {key, _options} -> Atom.to_string(key) end)
      |> Enum.sort()

    %{
      "$schema" => "https://json-schema.org/draft/2020-12/schema",
      "additionalProperties" => true,
      "properties" => properties,
      "required" => required,
      "type" => "object"
    }
    |> normalize_json_schema()
  end

  defp json_type(:string), do: %{"type" => "string"}
  defp json_type(:integer), do: %{"type" => "integer"}
  defp json_type(:boolean), do: %{"type" => "boolean"}
  defp json_type(:float), do: %{"type" => "number"}
  defp json_type(:number), do: %{"type" => "number"}
  defp json_type(:non_neg_integer), do: %{"minimum" => 0, "type" => "integer"}
  defp json_type(:pos_integer), do: %{"minimum" => 1, "type" => "integer"}

  defp json_type(:timeout) do
    %{
      "anyOf" => [
        %{"minimum" => 0, "type" => "integer"},
        %{"const" => "infinity"}
      ]
    }
  end

  defp json_type(:atom), do: %{"type" => "string"}
  defp json_type(:any), do: %{}

  defp json_type({:list, subtype}) do
    %{"items" => json_type(subtype), "type" => "array"}
  end

  defp json_type({:in, values}) do
    %{
      "enum" => Enum.map(values, &enum_json_value/1),
      "type" => enum_json_type(values)
    }
  end

  defp enum_json_type(values) do
    cond do
      Enum.all?(values, &is_integer/1) -> "integer"
      Enum.all?(values, &is_number/1) -> "number"
      Enum.all?(values, &is_boolean/1) -> "boolean"
      true -> "string"
    end
  end

  defp enum_json_value(value) when is_atom(value), do: Atom.to_string(value)
  defp enum_json_value(value), do: value

  defp maybe_put_default(property, %{default: default}), do: Map.put(property, "default", default)
  defp maybe_put_default(property, _options), do: property

  defp sample_params(schema) do
    Map.new(schema, fn {key, options} -> {key, sample_value(options.type, key)} end)
  end

  defp required_params(schema) do
    schema
    |> Enum.filter(fn {_key, options} -> Map.get(options, :required, false) end)
    |> Map.new(fn {key, options} -> {key, sample_value(options.type, key)} end)
  end

  defp default_params(schema) do
    schema
    |> Enum.filter(fn {_key, options} -> Map.has_key?(options, :default) end)
    |> Map.new(fn {key, options} -> {key, options.default} end)
  end

  defp sample_value(:string, key), do: "sample_#{key}"
  defp sample_value(:integer, _key), do: 7
  defp sample_value(:boolean, _key), do: true
  defp sample_value(:float, _key), do: 1.5
  defp sample_value(:number, _key), do: 2
  defp sample_value(:non_neg_integer, _key), do: 0
  defp sample_value(:pos_integer, _key), do: 1
  defp sample_value(:timeout, _key), do: 1
  defp sample_value(:atom, _key), do: :contract_sample
  defp sample_value(:any, _key), do: {:contract, :sample}
  defp sample_value({:list, subtype}, key), do: [sample_value(subtype, key)]
  defp sample_value({:in, [value | _values]}, _key), do: value

  defp normalize_json_schema(schema) do
    schema
    |> Jason.encode!()
    |> Jason.decode!()
    |> sort_json_schema()
  end

  defp sort_json_schema(schema) when is_map(schema) do
    Map.new(schema, fn
      {"enum", values} -> {"enum", Enum.sort(values)}
      {"required", values} -> {"required", Enum.sort(values)}
      {key, value} -> {key, sort_json_schema(value)}
    end)
  end

  defp sort_json_schema(values) when is_list(values), do: Enum.map(values, &sort_json_schema/1)
  defp sort_json_schema(value), do: value
end
