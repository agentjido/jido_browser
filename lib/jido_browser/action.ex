defmodule Jido.Browser.Action do
  @moduledoc false

  defmacro __using__(opts) do
    quote do
      use Jido.Action, unquote(opts)

      @impl Jido.Action
      def on_after_validate_params(params) do
        {:ok, Jido.Browser.Action.apply_schema_defaults(schema(), params)}
      end
    end
  end

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
