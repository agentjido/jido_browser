defmodule Jido.Browser.WebFetch.Backends.Req do
  @moduledoc """
  Default `Req` transport backend for `Jido.Browser.web_fetch/2`.
  """

  @behaviour Jido.Browser.WebFetch.Backend

  alias Jido.Browser.Error

  @destination_address_key :jido_browser_destination_address
  @pinned_adapter Jido.Browser.WebFetch.Backends.Req.PinnedFinch

  @impl true
  def fetch(url, opts) do
    case Req.run(request_options(url, opts)) do
      {%Req.Request{} = request, %Req.Response{} = response} ->
        {:ok,
         %{
           status: response.status,
           headers: response.headers,
           body: response.body,
           final_url: final_url(request)
         }}

      {_request, %Req.TransportError{} = exception} ->
        {:error, Error.adapter_error("Web fetch request failed", %{error_code: :url_not_accessible, reason: exception})}

      {_request, %Req.TooManyRedirectsError{} = exception} ->
        {:error,
         Error.adapter_error("Web fetch exceeded redirect limit", %{error_code: :url_not_accessible, reason: exception})}

      {_request, %_{} = exception} ->
        {:error, Error.adapter_error("Web fetch failed", %{error_code: :unavailable, reason: exception})}
    end
  end

  @doc false
  @spec request_options(String.t(), keyword()) :: keyword()
  def request_options(url, opts) do
    [
      url: url,
      headers: request_headers(),
      receive_timeout: opts[:timeout],
      decode_body: false,
      redirect: false
    ]
    |> Keyword.merge(opts[:req] || [])
    |> Keyword.put(:url, url)
    |> Keyword.put(:decode_body, false)
    |> Keyword.put(:redirect, false)
    |> maybe_pin_destination(url, opts)
  end

  defp maybe_pin_destination(request_opts, url, opts) do
    if Keyword.has_key?(opts, :destination_address) do
      pin_destination(request_opts, url, opts)
    else
      request_opts
    end
  end

  defp pin_destination(request_opts, url, opts) do
    destination_address = Keyword.fetch!(opts, :destination_address)
    uri = URI.parse(url)
    hostname = uri.host

    connect_options =
      request_opts
      |> Keyword.get(:connect_options, [])
      |> Keyword.delete(:proxy)
      |> Keyword.delete(:proxy_headers)
      |> Keyword.put(:hostname, hostname)
      |> put_address_family(destination_address)
      |> force_http1_for_ipv6_literal(uri)

    finch_private =
      request_opts
      |> Keyword.get(:finch_private, %{})
      |> Map.new()
      |> Map.put(@destination_address_key, destination_address)

    request_opts
    |> Keyword.delete(:finch)
    |> Keyword.delete(:finch_request)
    |> Keyword.delete(:plug)
    |> Keyword.put(:adapter, @pinned_adapter)
    |> Keyword.put(:connect_options, connect_options)
    |> Keyword.put(:finch_private, finch_private)
  end

  defp put_address_family(connect_options, {_a, _b, _c, _d}) do
    update_transport_options(connect_options, inet4: true, inet6: false)
  end

  defp put_address_family(connect_options, {_a, _b, _c, _d, _e, _f, _g, _h}) do
    update_transport_options(connect_options, inet4: false, inet6: true)
  end

  defp update_transport_options(connect_options, address_family) do
    transport_options =
      connect_options
      |> Keyword.get(:transport_opts, [])
      |> Keyword.merge(address_family)

    Keyword.put(connect_options, :transport_opts, transport_options)
  end

  # Mint 1.9 derives the HTTP/2 :authority value from its TLS hostname and does
  # not add brackets for IPv6. Keep the TLS hostname unbracketed and use HTTP/1,
  # where the pinned adapter can set a valid bracketed Host value.
  defp force_http1_for_ipv6_literal(connect_options, %URI{host: host}) do
    case :inet.parse_address(String.to_charlist(host)) do
      {:ok, {_a, _b, _c, _d, _e, _f, _g, _h}} -> Keyword.put(connect_options, :protocols, [:http1])
      _other -> connect_options
    end
  end

  defp final_url(%Req.Request{url: %URI{} = uri}) do
    uri
    |> normalize_uri()
    |> URI.to_string()
  end

  defp normalize_uri(%URI{} = uri) do
    %{uri | host: String.downcase(uri.host || ""), fragment: nil}
  end

  defp request_headers do
    [
      {"accept",
       "text/html,application/xhtml+xml,text/plain,application/json,application/pdf," <>
         "application/msword,application/vnd.openxmlformats-officedocument.wordprocessingml.document," <>
         "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet," <>
         "application/vnd.openxmlformats-officedocument.presentationml.presentation,*/*;q=0.1"},
      {"user-agent", user_agent()}
    ]
  end

  defp user_agent do
    vsn =
      case Application.spec(:jido_browser, :vsn) do
        nil -> "dev"
        value -> List.to_string(value)
      end

    "jido_browser/#{vsn}"
  end
end
