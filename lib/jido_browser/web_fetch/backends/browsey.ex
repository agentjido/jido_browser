defmodule Jido.Browser.WebFetch.Backends.Browsey do
  @moduledoc """
  Optional BrowseyHttp transport backend for `Jido.Browser.web_fetch/2`.

  This backend uses a private vendored copy of BrowseyHttp so `jido_browser`
  remains publishable as a Hex package while upstream BrowseyHttp is only
  distributed from GitHub.
  """

  @behaviour Jido.Browser.WebFetch.Backend

  alias Jido.Browser.Error
  alias Jido.Browser.Vendor.BrowseyHttp

  @default_client BrowseyHttp
  @default_timeout 30_000
  @default_max_redirects 5

  @impl true
  def fetch(url, opts) do
    browsey_opts =
      opts
      |> Keyword.get(:browsey, [])
      |> Keyword.put_new(:timeout, opts[:timeout] || @default_timeout)
      |> Keyword.put_new(:follow_redirects?, Keyword.get(opts, :max_redirects, @default_max_redirects) > 0)

    {client, browsey_opts} = Keyword.pop(browsey_opts, :client, @default_client)

    with :ok <- ensure_client(client) do
      case client.get(url, browsey_opts) do
        {:ok, response} ->
          normalize_response(response, url)

        {:error, exception} ->
          {:error,
           Error.adapter_error("BrowseyHttp request failed", %{
             error_code: browsey_error_code(exception),
             backend: __MODULE__,
             reason: exception
           })}
      end
    end
  rescue
    error ->
      {:error,
       Error.adapter_error("BrowseyHttp request failed", %{
         error_code: :unavailable,
         backend: __MODULE__,
         reason: error
       })}
  end

  defp ensure_client(client) when is_atom(client) do
    if Code.ensure_loaded?(client) and function_exported?(client, :get, 2) do
      :ok
    else
      {:error,
       Error.adapter_error("BrowseyHttp backend is unavailable", %{
         error_code: :backend_unavailable,
         backend: __MODULE__,
         dependency: :vendored_browsey_http,
         client: client
       })}
    end
  end

  defp normalize_response(%{status: status, headers: headers, body: body} = response, fallback_url)
       when is_integer(status) and is_map(headers) and is_binary(body) do
    {:ok,
     %{
       status: status,
       headers: headers,
       body: body,
       final_url: final_url(response, fallback_url)
     }}
  end

  defp normalize_response(response, _fallback_url) do
    {:error,
     Error.adapter_error("BrowseyHttp returned an unexpected response", %{
       error_code: :unavailable,
       backend: __MODULE__,
       response: response
     })}
  end

  defp final_url(%{final_url: final_url}, _fallback_url) when is_binary(final_url), do: final_url
  defp final_url(%{final_uri: %URI{} = uri}, _fallback_url), do: uri |> normalize_uri() |> URI.to_string()
  defp final_url(%{uri_sequence: [_ | _] = uris}, fallback_url), do: uris |> List.last() |> final_url(fallback_url)
  defp final_url(%URI{} = uri, _fallback_url), do: uri |> normalize_uri() |> URI.to_string()
  defp final_url(_response, fallback_url), do: fallback_url

  defp normalize_uri(%URI{} = uri) do
    %{uri | host: String.downcase(uri.host || ""), fragment: nil}
  end

  defp browsey_error_code(%{__struct__: module}) do
    module
    |> Module.split()
    |> List.last()
    |> case do
      "TimeoutException" -> :timeout
      "TooLargeException" -> :response_too_large
      "TooManyRedirectsException" -> :url_not_accessible
      "ConnectionException" -> :url_not_accessible
      "SslException" -> :url_not_accessible
      _ -> :unavailable
    end
  end

  defp browsey_error_code(_exception), do: :unavailable
end
