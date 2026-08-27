defmodule Jido.Browser.ActionContractAssertions do
  @moduledoc false

  import ExUnit.Assertions

  alias Jido.Action.Tool

  @unknown_atom :contract_unknown_atom
  @unknown_string "contract_unknown_string"

  def assert_contract(%{module: action, name: name, description: description, schema: schema}) do
    assert normalized_schema(action.schema()) == normalized_schema(schema)

    assert_validation_contract(action, schema)
    assert_tool_input_contract(action, schema)
    assert_generated_tool_contract(action, name, description, schema)
  end

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

  defp assert_tool_input_contract(action, schema) do
    all_atom_params = sample_params(schema)
    all_string_params = Map.new(all_atom_params, fn {key, value} -> {Atom.to_string(key), value} end)

    assert Tool.convert_params_using_schema(all_string_params, action.schema()) == all_atom_params

    params_with_unknown_keys =
      Map.merge(all_string_params, %{@unknown_atom => :kept, @unknown_string => "kept"})

    assert Tool.convert_params_using_schema(params_with_unknown_keys, action.schema()) ==
             Map.merge(all_atom_params, %{@unknown_atom => :kept, @unknown_string => "kept"})

    assert_atom_key_precedence(action, schema)
  end

  defp assert_atom_key_precedence(_action, schema) when map_size(schema) == 0, do: :ok

  defp assert_atom_key_precedence(action, schema) do
    {key, options} = Enum.at(schema, 0)
    atom_value = sample_value(options.type, key)
    string_value = alternate_sample_value(options.type, key)

    params = %{key => atom_value, Atom.to_string(key) => string_value}

    assert Tool.convert_params_using_schema(params, action.schema()) == %{key => atom_value}
  end

  defp assert_generated_tool_contract(action, name, description, schema) do
    tool = action.to_tool()

    assert Map.keys(tool) |> Enum.sort() == [:description, :function, :name, :parameters_schema]
    assert tool.name == name
    assert tool.description == description
    assert is_function(tool.function, 2)
    assert normalize_json_schema(tool.parameters_schema) == expected_tool_schema(schema)
  end

  defp expected_tool_schema(schema) do
    properties =
      Map.new(schema, fn {key, options} ->
        property =
          options.type
          |> json_type()
          |> Map.put("description", options.doc)

        {Atom.to_string(key), property}
      end)

    required =
      schema
      |> Enum.filter(fn {_key, options} -> Map.get(options, :required, false) end)
      |> Enum.map(fn {key, _options} -> Atom.to_string(key) end)
      |> Enum.sort()

    %{
      "additionalProperties" => false,
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
      "oneOf" => [
        %{"minimum" => 0, "type" => "integer"},
        %{"enum" => ["infinity"], "type" => "string"}
      ]
    }
  end

  defp json_type(:atom), do: %{"type" => "string"}
  defp json_type(:any), do: %{"type" => "string"}

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

  defp alternate_sample_value(:string, key), do: "alternate_#{key}"
  defp alternate_sample_value(:integer, _key), do: 9
  defp alternate_sample_value(:boolean, _key), do: false
  defp alternate_sample_value(:float, _key), do: 2.5
  defp alternate_sample_value(:number, _key), do: 3
  defp alternate_sample_value(:non_neg_integer, _key), do: 2
  defp alternate_sample_value(:pos_integer, _key), do: 2
  defp alternate_sample_value(:timeout, _key), do: 2
  defp alternate_sample_value(:atom, _key), do: :contract_alternate
  defp alternate_sample_value(:any, _key), do: {:contract, :alternate}
  defp alternate_sample_value({:list, subtype}, key), do: [alternate_sample_value(subtype, key)]
  defp alternate_sample_value({:in, values}, _key), do: List.last(values)

  defp normalized_schema(schema) do
    Map.new(schema, fn {key, options} ->
      normalized_options =
        options
        |> Map.new()
        |> Map.update(:type, nil, &normalize_type/1)

      {key, normalized_options}
    end)
  end

  defp normalize_type({:in, values}), do: {:in, Enum.sort(values)}
  defp normalize_type(type), do: type

  defp normalize_json_schema(schema) when is_map(schema) do
    Map.new(schema, fn
      {"enum", values} -> {"enum", Enum.sort(values)}
      {"required", values} -> {"required", Enum.sort(values)}
      {key, value} -> {key, normalize_json_schema(value)}
    end)
  end

  defp normalize_json_schema(values) when is_list(values), do: Enum.map(values, &normalize_json_schema/1)
  defp normalize_json_schema(value), do: value
end
