defmodule Jido.Browser.WebFetch.Backend do
  @moduledoc """
  HTTP transport behaviour for `Jido.Browser.WebFetch`.

  Backends fetch bytes and response metadata only. `Jido.Browser.WebFetch`
  remains responsible for URL policy, content-type handling, document
  extraction, filtering, citations, truncation, and cache storage.
  """

  @type response :: %{
          required(:status) => non_neg_integer(),
          required(:headers) => %{optional(String.t()) => [String.t()] | String.t()},
          required(:body) => binary(),
          required(:final_url) => String.t()
        }

  @callback fetch(String.t(), keyword()) :: {:ok, response()} | {:error, Exception.t()}
end
