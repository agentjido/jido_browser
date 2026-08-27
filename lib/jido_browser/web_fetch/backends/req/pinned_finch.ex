defmodule Jido.Browser.WebFetch.Backends.Req.PinnedFinch do
  @moduledoc false

  @destination_address_key :jido_browser_destination_address
  @request_option_keys [:pool_timeout, :receive_timeout, :request_timeout]

  @doc false
  @spec run(Req.Request.t()) :: {Req.Request.t(), Req.Response.t() | Exception.t()}
  def run(%Req.Request{} = request) do
    with {:ok, finch_name} <- ensure_finch_pool(request),
         finch_request <- build_finch_request(request),
         request_options <- finch_request_options(request),
         {:ok, response} <- Finch.request(finch_request, finch_name, request_options) do
      {request, Req.Response.new(response)}
    else
      {:error, error} -> {request, normalize_error(error)}
    end
  rescue
    error -> {request, error}
  end

  defp ensure_finch_pool(request) do
    pool_options = Req.Finch.pool_options(request.options)
    finch_name = Req.Finch.pool_name(pool_options)

    case DynamicSupervisor.start_child(
           Req.FinchSupervisor,
           {Finch, name: finch_name, pools: %{default: pool_options}}
         ) do
      {:ok, _pid} -> {:ok, finch_name}
      {:error, {:already_started, _pid}} -> {:ok, finch_name}
      {:error, reason} -> {:error, RuntimeError.exception("failed to start pinned Finch pool: #{inspect(reason)}")}
    end
  end

  @doc false
  @spec build_finch_request(Req.Request.t()) :: Finch.Request.t()
  def build_finch_request(request) do
    request = put_ipv6_host_header(request)

    request.method
    |> Finch.build(request.url, Req.Fields.get_list(request.headers), request.body)
    |> Map.put(:host, destination_address!(request))
    |> add_private_options(request.options[:finch_private])
  end

  @doc false
  @spec origin_authority(URI.t()) :: String.t()
  def origin_authority(%URI{host: host} = uri) do
    host = if String.contains?(host, ":"), do: "[#{host}]", else: host

    if uri.port == URI.default_port(uri.scheme) do
      host
    else
      "#{host}:#{uri.port}"
    end
  end

  defp finch_request_options(request) do
    request.options
    |> Map.take(@request_option_keys)
    |> Enum.to_list()
  end

  defp add_private_options(finch_request, private_options) do
    private_options
    |> Map.new()
    |> Enum.reduce(finch_request, fn {key, value}, request ->
      Finch.Request.put_private(request, key, value)
    end)
  end

  defp put_ipv6_host_header(%Req.Request{url: %URI{host: host} = uri} = request) do
    case :inet.parse_address(String.to_charlist(host)) do
      {:ok, {_a, _b, _c, _d, _e, _f, _g, _h}} ->
        Req.Request.put_new_header(request, "host", origin_authority(uri))

      _other ->
        request
    end
  end

  defp normalize_error(%Finch.TransportError{reason: reason}), do: %Req.TransportError{reason: reason}
  defp normalize_error(%Mint.TransportError{reason: reason}), do: %Req.TransportError{reason: reason}

  defp normalize_error(%Finch.HTTPError{module: module, reason: reason}) do
    %Req.HTTPError{protocol: protocol(module), reason: reason}
  end

  defp normalize_error(%Mint.HTTPError{module: module, reason: reason}) do
    %Req.HTTPError{protocol: protocol(module), reason: reason}
  end

  defp normalize_error(%Finch.Error{reason: reason}), do: %Req.HTTPError{protocol: :http1, reason: reason}
  defp normalize_error(error) when is_exception(error), do: error
  defp normalize_error(error), do: RuntimeError.exception("pinned Finch request failed: #{inspect(error)}")

  defp protocol(Mint.HTTP2), do: :http2
  defp protocol(_module), do: :http1

  defp destination_address!(request) do
    request.options
    |> Map.fetch!(:finch_private)
    |> Map.new()
    |> Map.fetch!(@destination_address_key)
  end
end
