defmodule Jido.Browser.Vendor.BrowseyHttp.ProcessCleanupException do
  @moduledoc false

  defexception [:message, :uri, :reason]

  @type t() :: %__MODULE__{
          message: String.t(),
          uri: URI.t(),
          reason: term()
        }

  @spec new(URI.t(), term()) :: t()
  def new(%URI{} = uri, reason) do
    %__MODULE__{
      message: "Request process cleanup failed",
      uri: uri,
      reason: reason
    }
  end
end
