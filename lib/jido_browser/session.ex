defmodule JidoBrowser.Session do
  @moduledoc """
  Represents an active browser session.

  A session holds the connection state to a browser instance and tracks
  the adapter being used for communication.
  """

  @schema Zoi.struct(
            __MODULE__,
            %{
              id: Zoi.string(),
              adapter: Zoi.any(),
              connection: Zoi.any() |> Zoi.nullish(),
              started_at: Zoi.any(),
              opts: Zoi.any() |> Zoi.default(%{})
            },
            coerce: true
          )

  @type t :: %__MODULE__{
          id: String.t(),
          adapter: module(),
          connection: term(),
          started_at: DateTime.t(),
          opts: map()
        }

  @enforce_keys [:id, :adapter, :started_at]
  defstruct [:id, :adapter, :connection, :started_at, opts: %{}]

  @doc """
  Returns the Zoi schema for this struct.
  """
  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @doc """
  Creates a new session struct.

  ## Examples

      session = JidoBrowser.Session.new!(
        id: "sess_abc123",
        adapter: JidoBrowser.Adapters.Vibium,
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
