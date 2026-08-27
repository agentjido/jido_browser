defmodule Jido.Browser.Vendor.BrowseyHttp.TooLargeException do
  @moduledoc false
  defexception [:message, :uri, :max_bytes, :observed_bytes, :declared_bytes]

  @type t() :: %__MODULE__{
          message: String.t(),
          uri: URI.t(),
          max_bytes: non_neg_integer(),
          observed_bytes: non_neg_integer(),
          declared_bytes: non_neg_integer() | nil
        }

  @spec new(URI.t(), non_neg_integer(), non_neg_integer(), non_neg_integer() | nil) :: t()
  def new(%URI{} = uri, bytes, observed_bytes \\ 0, declared_bytes \\ nil) do
    %__MODULE__{
      message: "Response body exceeds #{format_bytes(bytes)}",
      uri: uri,
      max_bytes: bytes,
      observed_bytes: observed_bytes,
      declared_bytes: declared_bytes
    }
  end

  defp format_bytes(bytes) do
    bytes_to_mb = 1024 * 1024

    if rem(bytes, bytes_to_mb) == 0 do
      mb = div(bytes, bytes_to_mb)
      "#{mb} MB"
    else
      "#{bytes} bytes"
    end
  end
end
