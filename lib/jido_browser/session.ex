defmodule Jido.Browser.Session do
  @moduledoc """
  Represents an active browser session.

  A session holds the connection state to a browser instance and tracks
  the adapter being used for communication.
  """

  @schema Zoi.struct(
            __MODULE__,
            %{
              id: Zoi.string(typespec: quote(do: String.t())),
              adapter: Zoi.any(typespec: quote(do: module())),
              connection: Zoi.any() |> Zoi.nullish(typespec: quote(do: term())),
              runtime: Zoi.any() |> Zoi.nullish(typespec: quote(do: map() | nil)),
              capabilities: Zoi.any() |> Zoi.default(%{}, typespec: quote(do: map())),
              started_at: Zoi.any(typespec: quote(do: DateTime.t())),
              opts: Zoi.any() |> Zoi.default(%{}, typespec: quote(do: map()))
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc """
  Returns the Zoi schema for this struct.
  """
  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @doc """
  Creates a new session struct.

  ## Examples

      session = Jido.Browser.Session.new!(
        id: "sess_abc123",
        adapter: Jido.Browser.Adapters.Vibium,
        connection: pid
      )

  """
  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs) do
    attrs = Map.put_new(attrs, :started_at, DateTime.utc_now())
    attrs = Map.put_new_lazy(attrs, :id, fn -> Uniq.UUID.uuid4() end)
    Zoi.parse(@schema, attrs)
  end

  @doc """
  Like `new/1` but raises on validation errors.
  """
  @spec new!(map()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, session} -> session
      {:error, reason} -> raise ArgumentError, "Invalid session: #{inspect(reason)}"
    end
  end
end
