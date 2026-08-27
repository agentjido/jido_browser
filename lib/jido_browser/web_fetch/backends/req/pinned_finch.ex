defmodule Jido.Browser.WebFetch.Backends.Req.PinnedFinch do
  @moduledoc false

  @destination_address_key :jido_browser_destination_address
  @response_limit_key :jido_browser_max_response_bytes
  @response_too_large_tag :jido_browser_response_too_large
  @request_option_keys [:pool_timeout, :receive_timeout, :request_timeout]

  @doc false
  @spec run(Req.Request.t()) :: {Req.Request.t(), Req.Response.t() | Exception.t()}
  def run(%Req.Request{} = request) do
    with {:ok, finch_name} <- ensure_finch_pool(request),
         finch_request <- build_finch_request(request),
         request_options <- finch_request_options(request),
         {:ok, response} <- run_finch_request(request, finch_request, finch_name, request_options) do
      {request, response}
    else
      {:error, error} -> {request, normalize_error(error)}
    end
  rescue
    error -> {request, error}
  end

  @doc false
  @spec response_limit_error(Req.Response.t()) :: {:ok, map()} | :error
  def response_limit_error(%Req.Response{body: {@response_too_large_tag, details}}) when is_map(details),
    do: {:ok, details}

  def response_limit_error(%Req.Response{}), do: :error

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
    |> maybe_put_destination_address(request)
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

  defp run_finch_request(request, finch_request, finch_name, request_options) do
    case max_response_bytes(request) do
      :infinity ->
        with {:ok, response} <- Finch.request(finch_request, finch_name, request_options) do
          {:ok, Req.Response.new(response)}
        end

      max_response_bytes ->
        stream_finch_request(
          request,
          finch_request,
          finch_name,
          request_options,
          max_response_bytes
        )
    end
  end

  defp stream_finch_request(request, finch_request, finch_name, request_options, max_response_bytes) do
    state = %{
      body: [],
      decode_error: nil,
      decode_response?: decode_response?(request),
      decoders: [],
      declared_response_bytes: nil,
      headers: [],
      max_response_bytes: max_response_bytes,
      transfer_response_bytes: 0,
      unknown_content_encodings: [],
      status: nil,
      too_large: nil,
      trailers: []
    }

    stream_fun = fn
      {:status, status}, state ->
        {:cont, %{state | status: status}}

      {:headers, headers}, state ->
        state =
          state
          |> Map.update!(:headers, &(&1 ++ headers))
          |> maybe_initialize_decoders(request)

        maybe_halt_for_declared_size(request, state)

      {:data, data}, state ->
        maybe_collect_data(state, data)

      {:trailers, trailers}, state ->
        {:cont, %{state | trailers: state.trailers ++ trailers}}
    end

    case Finch.stream_while(finch_request, finch_name, state, stream_fun, request_options) do
      {:ok, state} ->
        state = finalize_decoders(state)
        close_decoders(state.decoders)

        case state.decode_error do
          nil -> {:ok, response_from_state(state)}
          exception -> {:error, exception}
        end

      {:error, error, state} ->
        close_decoders(state.decoders)
        {:error, error}
    end
  end

  defp maybe_halt_for_declared_size(request, state) do
    declared_response_bytes = declared_response_bytes(state.headers)
    state = %{state | declared_response_bytes: declared_response_bytes}

    if response_has_body?(request.method, state.status) and
         is_integer(declared_response_bytes) and
         declared_response_bytes > state.max_response_bytes do
      {:halt,
       mark_too_large(
         state,
         _observed_response_bytes = 0,
         declared_response_bytes
       )}
    else
      {:cont, state}
    end
  end

  defp maybe_collect_data(state, data) do
    transfer_response_bytes = state.transfer_response_bytes + byte_size(data)

    if transfer_response_bytes > state.max_response_bytes do
      {:halt,
       mark_too_large(
         state,
         transfer_response_bytes,
         state.declared_response_bytes,
         :transfer_body
       )}
    else
      state = %{state | transfer_response_bytes: transfer_response_bytes}

      case decode_data(state.decoders, data, state.max_response_bytes) do
        {:ok, decoders, decoded} ->
          {:cont, %{state | body: [state.body, decoded], decoders: decoders}}

        {:too_large, decoders, observed_response_bytes} ->
          state = %{state | decoders: decoders}

          {:halt,
           mark_too_large(
             state,
             observed_response_bytes,
             state.declared_response_bytes,
             :content_decoded
           )}

        {:error, decoders, exception} ->
          {:halt, %{state | body: [], decode_error: exception, decoders: decoders}}
      end
    end
  end

  defp mark_too_large(
         state,
         observed_response_bytes,
         declared_response_bytes,
         response_byte_semantics \\ :transfer_body
       ) do
    details = %{
      declared_response_bytes: declared_response_bytes,
      max_response_bytes: state.max_response_bytes,
      observed_response_bytes: observed_response_bytes,
      response_byte_semantics: response_byte_semantics
    }

    %{state | body: [], too_large: details}
  end

  defp response_from_state(%{too_large: details} = state) when is_map(details) do
    Req.Response.new(
      status: state.status || 0,
      headers: state.headers,
      body: {@response_too_large_tag, details},
      trailers: state.trailers
    )
  end

  defp response_from_state(state) do
    response =
      Req.Response.new(
        status: state.status || 0,
        headers: state.headers,
        body: IO.iodata_to_binary(state.body),
        trailers: state.trailers
      )

    normalize_decoded_headers(response, state)
  end

  defp maybe_initialize_decoders(%{decoders: [_ | _]} = state, _request), do: state
  defp maybe_initialize_decoders(%{decode_response?: false} = state, _request), do: state

  defp maybe_initialize_decoders(state, request) do
    if response_has_body?(request.method, state.status) do
      {decoders, unknown_content_encodings} = initialize_decoders(state.headers)

      %{
        state
        | decoders: decoders,
          unknown_content_encodings: unknown_content_encodings
      }
    else
      state
    end
  end

  defp initialize_decoders(headers) do
    headers
    |> content_encodings()
    |> Enum.reduce({[], []}, fn
      encoding, {decoders, unknown} when encoding in ["gzip", "x-gzip"] ->
        {[new_decoder(:gzip, Req.Gzip.decode_init()) | decoders], unknown}

      "br", {decoders, unknown} ->
        if Code.ensure_loaded?(:brotli) do
          {[new_decoder(:br, Req.Brotli.decode_init()) | decoders], unknown}
        else
          {decoders, ["br" | unknown]}
        end

      "zstd", {decoders, unknown} ->
        if Req.Utils.zstd_available?() do
          {[new_decoder(:zstd, Req.Zstd.decode_init()) | decoders], unknown}
        else
          {decoders, ["zstd" | unknown]}
        end

      "identity", accumulator ->
        accumulator

      encoding, {decoders, unknown} ->
        {decoders, [encoding | unknown]}
    end)
    |> then(fn {decoders, unknown} -> {Enum.reverse(decoders), unknown} end)
  end

  defp new_decoder(format, decoder_state) do
    %{closed?: false, format: format, observed_response_bytes: 0, state: decoder_state}
  end

  defp content_encodings(headers) do
    headers
    |> Enum.flat_map(fn {name, value} ->
      if String.downcase(name) == "content-encoding" do
        value
        |> String.downcase()
        |> String.split(",", trim: true)
        |> Enum.map(&String.trim/1)
      else
        []
      end
    end)
    |> Enum.reverse()
  end

  defp decode_data([], data, max_response_bytes) do
    if byte_size(data) > max_response_bytes do
      {:too_large, [], byte_size(data)}
    else
      {:ok, [], data}
    end
  end

  defp decode_data(decoders, data, max_response_bytes) do
    Enum.reduce_while(decoders, {:ok, [], data}, fn decoder, {:ok, processed, input} ->
      case decode_chunk(decoder, input, max_response_bytes) do
        {:ok, decoder, output} ->
          {:cont, {:ok, [decoder | processed], output}}

        {:too_large, decoder, observed_response_bytes} ->
          remaining = Enum.drop(decoders, length(processed) + 1)
          {:halt, {:too_large, Enum.reverse([decoder | processed]) ++ remaining, observed_response_bytes}}

        {:error, decoder, reason} ->
          remaining = Enum.drop(decoders, length(processed) + 1)
          exception = %Req.DecompressError{format: decoder.format, data: nil, reason: reason}
          {:halt, {:error, Enum.reverse([decoder | processed]) ++ remaining, exception}}
      end
    end)
    |> case do
      {:ok, processed, output} -> {:ok, Enum.reverse(processed), output}
      result -> result
    end
  end

  defp decode_chunk(%{format: :gzip} = decoder, input, max_response_bytes) do
    safe_inflate(decoder, input, max_response_bytes, [])
  rescue
    error in ErlangError ->
      if error.original == :data_error do
        {:error, decoder, :data_error}
      else
        reraise error, __STACKTRACE__
      end
  end

  defp decode_chunk(%{format: :br} = decoder, input, max_response_bytes) do
    bounded_decode_chunk(decoder, Req.Brotli.decode_chunk(decoder.state, input), max_response_bytes)
  end

  defp decode_chunk(%{format: :zstd} = decoder, input, max_response_bytes) do
    safe_zstd_stream(decoder, input, max_response_bytes, [])
  rescue
    error in ErlangError ->
      case error.original do
        {:zstd_error, reason} -> {:error, decoder, reason}
        _other -> reraise error, __STACKTRACE__
      end
  end

  defp safe_inflate(decoder, input, max_response_bytes, output) do
    case :zlib.safeInflate(decoder.state, input) do
      {status, inflated} when status in [:continue, :finished] ->
        inflated_size = IO.iodata_length(inflated)
        observed_response_bytes = decoder.observed_response_bytes + inflated_size
        decoder = %{decoder | observed_response_bytes: observed_response_bytes}

        if observed_response_bytes > max_response_bytes do
          {:too_large, decoder, observed_response_bytes}
        else
          output = [output, inflated]
          continue_safe_inflate(status, decoder, max_response_bytes, output)
        end
    end
  end

  defp continue_safe_inflate(:continue, decoder, max_response_bytes, output) do
    safe_inflate(decoder, [], max_response_bytes, output)
  end

  defp continue_safe_inflate(:finished, decoder, _max_response_bytes, output) do
    {:ok, decoder, IO.iodata_to_binary(output)}
  end

  defp bounded_decode_chunk(decoder, {:ok, output}, max_response_bytes) do
    observed_response_bytes = decoder.observed_response_bytes + byte_size(output)
    decoder = %{decoder | observed_response_bytes: observed_response_bytes}

    if observed_response_bytes > max_response_bytes do
      {:too_large, decoder, observed_response_bytes}
    else
      {:ok, decoder, output}
    end
  end

  defp bounded_decode_chunk(decoder, {:error, reason}, _max_response_bytes) do
    {:error, decoder, reason}
  end

  defp safe_zstd_stream(decoder, input, max_response_bytes, output) do
    case zstd_stream(decoder.state, input) do
      {:continue, decoded} ->
        case append_bounded_decoder_output(decoder, decoded, max_response_bytes, output) do
          {:ok, decoder, output} -> {:ok, decoder, IO.iodata_to_binary(output)}
          result -> result
        end

      {:continue, remainder, decoded} ->
        case append_bounded_decoder_output(decoder, decoded, max_response_bytes, output) do
          {:ok, decoder, output} ->
            safe_zstd_stream(decoder, remainder, max_response_bytes, output)

          result ->
            result
        end
    end
  end

  # Use a dynamic call because :zstd is available only on OTP 28 and later.
  defp zstd_stream(decoder, input), do: :erlang.apply(:zstd, :stream, [decoder, input])

  defp append_bounded_decoder_output(decoder, output, max_response_bytes, accumulated) do
    output_size = IO.iodata_length(output)
    observed_response_bytes = decoder.observed_response_bytes + output_size
    decoder = %{decoder | observed_response_bytes: observed_response_bytes}

    if observed_response_bytes > max_response_bytes do
      {:too_large, decoder, observed_response_bytes}
    else
      {:ok, decoder, [accumulated, output]}
    end
  end

  defp finalize_decoders(%{too_large: details} = state) when is_map(details), do: state
  defp finalize_decoders(%{decode_error: exception} = state) when not is_nil(exception), do: state
  defp finalize_decoders(%{decoders: []} = state), do: state

  defp finalize_decoders(state) do
    case finish_decoder_pipeline(state.decoders, state.max_response_bytes) do
      {:ok, decoders, output} ->
        %{state | body: [state.body, output], decoders: decoders}

      {:too_large, decoders, observed_response_bytes} ->
        state = %{state | decoders: decoders}

        mark_too_large(
          state,
          observed_response_bytes,
          state.declared_response_bytes,
          :content_decoded
        )

      {:error, decoders, exception} ->
        %{state | body: [], decode_error: exception, decoders: decoders}
    end
  end

  defp finish_decoder_pipeline([], _max_response_bytes), do: {:ok, [], ""}

  defp finish_decoder_pipeline([decoder | rest], max_response_bytes) do
    with {:ok, decoder, output} <- finish_decoder(decoder, max_response_bytes),
         {:ok, rest, output} <- decode_data(rest, output, max_response_bytes),
         {:ok, rest, final_output} <- finish_decoder_pipeline(rest, max_response_bytes) do
      {:ok, [decoder | rest], [output, final_output]}
    else
      {:too_large, decoder, observed_response_bytes} when is_map(decoder) ->
        {:too_large, [decoder | rest], observed_response_bytes}

      {:error, decoder, reason} when is_map(decoder) ->
        exception = %Req.DecompressError{format: decoder.format, data: nil, reason: reason}
        {:error, [decoder | rest], exception}

      {:too_large, rest, observed_response_bytes} ->
        {:too_large, [decoder | rest], observed_response_bytes}

      {:error, rest, exception} ->
        {:error, [decoder | rest], exception}
    end
  end

  defp finish_decoder(%{format: :gzip} = decoder, _max_response_bytes) do
    :ok = :zlib.inflateEnd(decoder.state)
    :ok = :zlib.close(decoder.state)
    {:ok, %{decoder | closed?: true}, ""}
  rescue
    error in ErlangError ->
      if error.original == :data_error do
        {:error, decoder, :data_error}
      else
        reraise error, __STACKTRACE__
      end
  end

  defp finish_decoder(%{format: :br} = decoder, max_response_bytes) do
    finish_bounded_decoder(decoder, Req.Brotli.decode_finish(decoder.state), max_response_bytes)
  end

  defp finish_decoder(%{format: :zstd} = decoder, max_response_bytes) do
    finish_bounded_decoder(decoder, Req.Zstd.decode_finish(decoder.state), max_response_bytes)
  end

  defp finish_bounded_decoder(decoder, result, max_response_bytes) do
    case bounded_decode_chunk(decoder, result, max_response_bytes) do
      {:ok, decoder, output} -> {:ok, %{decoder | closed?: true}, output}
      other -> other
    end
  end

  defp close_decoders(decoders) do
    Enum.each(decoders, fn
      %{closed?: true} -> :ok
      %{format: :gzip, state: decoder} -> safe_close(fn -> Req.Gzip.decode_close(decoder) end)
      %{format: :br, state: decoder} -> safe_close(fn -> Req.Brotli.decode_close(decoder) end)
      %{format: :zstd, state: decoder} -> safe_close(fn -> Req.Zstd.decode_close(decoder) end)
    end)
  end

  defp safe_close(fun) do
    fun.()
  rescue
    _error -> :ok
  end

  defp normalize_decoded_headers(response, %{decode_response?: true, unknown_content_encodings: []}) do
    Req.Response.delete_header(response, "content-encoding")
  end

  defp normalize_decoded_headers(response, %{
         decode_response?: true,
         unknown_content_encodings: unknown_content_encodings
       }) do
    Req.Response.put_header(response, "content-encoding", Enum.join(unknown_content_encodings, ", "))
  end

  defp normalize_decoded_headers(response, _state), do: response

  defp decode_response?(request) do
    Req.Request.get_option(request, :compressed, false) == true and request.options[:raw] != true
  end

  defp declared_response_bytes(headers) do
    values =
      for {name, value} <- headers,
          String.downcase(name) == "content-length",
          do: value

    case values do
      [value] -> parse_content_length(value)
      _other -> nil
    end
  end

  defp parse_content_length(value) do
    case Integer.parse(String.trim(value)) do
      {parsed, ""} when parsed >= 0 -> parsed
      _other -> nil
    end
  end

  defp response_has_body?(method, _status) when method in [:head, "HEAD", "head"], do: false
  defp response_has_body?(_method, status) when status in 100..199, do: false
  defp response_has_body?(_method, status) when status in [204, 304], do: false
  defp response_has_body?(_method, _status), do: true

  defp max_response_bytes(request) do
    request.options
    |> Map.get(:finch_private, %{})
    |> Map.new()
    |> Map.get(@response_limit_key, :infinity)
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

  defp maybe_put_destination_address(finch_request, request) do
    case destination_address(request) do
      nil -> finch_request
      address -> Map.put(finch_request, :host, address)
    end
  end

  defp destination_address(request) do
    request.options
    |> Map.get(:finch_private, %{})
    |> Map.new()
    |> Map.get(@destination_address_key)
  end
end
