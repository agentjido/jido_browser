defmodule Jido.Browser.WebFetch.Backends.Req do
  @moduledoc """
  Default `Req` transport backend for `Jido.Browser.web_fetch/2`.
  """

  @behaviour Jido.Browser.WebFetch.Backend

  alias Jido.Browser.Error

  @impl true
  def fetch(url, opts) do
    request_opts =
      [
        url: url,
        headers: request_headers(),
        receive_timeout: opts[:timeout],
        decode_body: false,
        redirect: true,
        max_redirects: opts[:max_redirects]
      ]
      |> Keyword.merge(opts[:req] || [])
      |> Keyword.put(:url, url)
      |> Keyword.put(:decode_body, false)

    case Req.run(request_opts) do
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
