defmodule Jido.Browser.Action do
  @moduledoc false

  defmacro __using__(opts) do
    opts =
      opts
      |> preserve_unknown_keys(:schema)
      |> preserve_unknown_keys(:output_schema)

    quote do
      use Jido.Action, unquote(opts)

      @impl Jido.Action
      def on_before_validate_params(params) do
        {:ok, Jido.Browser.Action.apply_schema_defaults(schema(), params)}
      end

      defoverridable on_before_validate_params: 1
    end
  end

  defp preserve_unknown_keys(opts, key) do
    case Keyword.fetch(opts, key) do
      {:ok, schema} ->
        Keyword.put(
          opts,
          key,
          quote do
            Jido.Browser.Action.preserve_unknown_keys(unquote(schema))
          end
        )

      :error ->
        opts
    end
  end

  @doc false
  @spec preserve_unknown_keys(Zoi.schema()) :: Zoi.schema()
  def preserve_unknown_keys(%Zoi.Types.Map{fields: fields} = schema) when is_list(fields),
    do: %{schema | unrecognized_keys: :preserve}

  def preserve_unknown_keys(schema), do: schema

  @doc false
  @spec apply_schema_defaults(Zoi.schema(), map()) :: map()
  def apply_schema_defaults(schema, params) when is_map(params) do
    schema
    |> Zoi.to_json_schema()
    |> Map.get(:properties, %{})
    |> Enum.reduce(params, fn {key, property}, acc ->
      case Map.fetch(property, :default) do
        {:ok, default} -> Map.put_new(acc, key, default)
        :error -> acc
      end
    end)
  end
end
