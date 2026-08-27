defmodule Jido.Browser.WebFetch.DestinationPolicy do
  @moduledoc false

  alias Jido.Browser.Error

  import Bitwise, only: [bsl: 2, bsr: 2]

  @policy_error_code :url_not_allowed
  # IANA IPv4 Special-Purpose Address Space plus the IPv4 multicast block.
  # https://www.iana.org/assignments/iana-ipv4-special-registry/
  @ipv4_special_ranges [
    {{0, 0, 0, 0}, 8, :this_network},
    {{10, 0, 0, 0}, 8, :private},
    {{100, 64, 0, 0}, 10, :shared_address_space},
    {{127, 0, 0, 0}, 8, :loopback},
    {{169, 254, 0, 0}, 16, :link_local},
    {{172, 16, 0, 0}, 12, :private},
    {{192, 0, 0, 0}, 24, :special_use},
    {{192, 0, 2, 0}, 24, :documentation},
    {{192, 31, 196, 0}, 24, :special_use},
    {{192, 52, 193, 0}, 24, :special_use},
    {{192, 88, 99, 0}, 24, :special_use},
    {{192, 168, 0, 0}, 16, :private},
    {{192, 175, 48, 0}, 24, :special_use},
    {{198, 18, 0, 0}, 15, :benchmarking},
    {{198, 51, 100, 0}, 24, :documentation},
    {{203, 0, 113, 0}, 24, :documentation},
    {{224, 0, 0, 0}, 4, :multicast},
    {{240, 0, 0, 0}, 4, :reserved}
  ]
  # IANA IPv6 Special-Purpose Address Space. All other allowed IPv6 addresses
  # must also be in the global-unicast 2000::/3 block.
  # https://www.iana.org/assignments/iana-ipv6-special-registry/
  @ipv6_special_ranges [
    {{0, 0, 0, 0, 0, 0, 0, 0}, 128, :unspecified},
    {{0, 0, 0, 0, 0, 0, 0, 1}, 128, :loopback},
    {{0, 0, 0, 0, 0, 0xFFFF, 0, 0}, 96, :ipv4_mapped},
    {{0x0064, 0xFF9B, 0, 0, 0, 0, 0, 0}, 96, :translation},
    {{0x0064, 0xFF9B, 1, 0, 0, 0, 0, 0}, 48, :translation},
    {{0x0100, 0, 0, 0, 0, 0, 0, 0}, 64, :discard_only},
    {{0x0100, 0, 0, 1, 0, 0, 0, 0}, 64, :special_use},
    {{0x2001, 0, 0, 0, 0, 0, 0, 0}, 23, :special_use},
    {{0x2001, 0x0DB8, 0, 0, 0, 0, 0, 0}, 32, :documentation},
    {{0x2002, 0, 0, 0, 0, 0, 0, 0}, 16, :special_use},
    {{0x2620, 0x004F, 0x8000, 0, 0, 0, 0, 0}, 48, :special_use},
    {{0x3FFF, 0, 0, 0, 0, 0, 0, 0}, 20, :documentation},
    {{0x5F00, 0, 0, 0, 0, 0, 0, 0}, 16, :special_use},
    {{0xFC00, 0, 0, 0, 0, 0, 0, 0}, 7, :private},
    {{0xFE80, 0, 0, 0, 0, 0, 0, 0}, 10, :link_local},
    {{0xFF00, 0, 0, 0, 0, 0, 0, 0}, 8, :multicast}
  ]
  @ipv6_global_unicast {{0x2000, 0, 0, 0, 0, 0, 0, 0}, 3}

  @doc false
  @spec prepare(String.t(), keyword()) :: {:ok, keyword()} | {:error, Exception.t()}
  def prepare(url, opts) do
    uri = URI.parse(url)

    case validate_pinnable_backend(opts) do
      :ok ->
        with {:ok, addresses} <- resolve_destination_addresses(uri.host, opts),
             :ok <- maybe_validate_destination_addresses(addresses, url, opts) do
          {:ok, Keyword.put(opts, :destination_addresses, addresses)}
        end

      {:error, _reason} = error ->
        if opts[:allow_private_network] do
          {:ok, Keyword.delete(opts, :destination_address)}
        else
          error
        end
    end
  end

  defp maybe_validate_destination_addresses(addresses, url, opts) do
    if opts[:allow_private_network], do: :ok, else: validate_destination_addresses(addresses, url)
  end

  defp validate_pinnable_backend(opts) do
    backend = opts[:backend]

    validate_pinnable_backend(backend, opts)
  end

  defp validate_pinnable_backend(backend, opts)
       when backend in [Jido.Browser.WebFetch.Backends.Req, Jido.Browser.WebFetch.Backends.Browsey] do
    if backend == Jido.Browser.WebFetch.Backends.Req and req_uses_proxy?(opts[:req]) do
      destination_policy_error("Web fetch proxy settings require allow_private_network", %{
        backend: backend
      })
    else
      :ok
    end
  end

  defp validate_pinnable_backend(backend, _opts) do
    destination_policy_error("Web fetch backend cannot enforce destination address pinning", %{
      backend: backend
    })
  end

  defp req_uses_proxy?(req_opts) when is_list(req_opts) do
    case Keyword.get(req_opts, :connect_options, []) do
      connect_options when is_list(connect_options) -> Keyword.has_key?(connect_options, :proxy)
      _other -> false
    end
  end

  defp req_uses_proxy?(_req_opts), do: false

  defp resolve_destination_addresses(host, opts) do
    case parse_address(host) do
      {:ok, address} ->
        {:ok, [address]}

      :error ->
        host
        |> run_resolver(opts[:resolver] || config(:resolver, nil))
        |> normalize_resolver_result(host)
    end
  end

  defp run_resolver(host, nil), do: system_resolve(host)
  defp run_resolver(host, resolver) when is_function(resolver, 1), do: resolver.(host)

  defp run_resolver(host, resolver) when is_atom(resolver) do
    if Code.ensure_loaded?(resolver) and function_exported?(resolver, :resolve, 1) do
      resolver.resolve(host)
    else
      {:error, {:invalid_resolver, resolver}}
    end
  end

  defp run_resolver(_host, resolver), do: {:error, {:invalid_resolver, resolver}}

  defp system_resolve(host) do
    encoded_host = String.to_charlist(host)
    ipv4_result = :inet.getaddrs(encoded_host, :inet)
    ipv6_result = :inet.getaddrs(encoded_host, :inet6)

    addresses =
      [ipv4_result, ipv6_result]
      |> Enum.flat_map(fn
        {:ok, values} -> values
        {:error, _reason} -> []
      end)

    case addresses do
      [] -> {:error, {ipv4_result, ipv6_result}}
      values -> {:ok, values}
    end
  end

  defp normalize_resolver_result({:ok, addresses}, host) do
    addresses = addresses |> List.wrap() |> Enum.uniq()

    cond do
      addresses == [] ->
        destination_policy_error("Web fetch destination did not resolve to an address", %{host: host})

      Enum.all?(addresses, &valid_address?/1) ->
        {:ok, addresses}

      true ->
        destination_policy_error("Web fetch resolver returned an invalid address", %{
          host: host,
          addresses: addresses
        })
    end
  end

  defp normalize_resolver_result({:error, reason}, host) do
    destination_policy_error("Web fetch destination could not be resolved", %{
      host: host,
      reason: reason
    })
  end

  defp normalize_resolver_result(result, host) do
    destination_policy_error("Web fetch resolver returned an invalid result", %{
      host: host,
      result: result
    })
  end

  defp validate_destination_addresses(addresses, url) do
    case Enum.find(addresses, &blocked_address?/1) do
      nil ->
        :ok

      address ->
        destination_policy_error("Web fetch destination address is not allowed", %{
          url: url,
          address: address_to_string(address),
          policy_reason: blocked_address_reason(address)
        })
    end
  end

  defp blocked_address?(address), do: not is_nil(blocked_address_reason(address))

  defp parse_address(host) when is_binary(host) do
    case :inet.parse_address(String.to_charlist(host)) do
      {:ok, address} -> {:ok, address}
      {:error, :einval} -> :error
    end
  end

  defp valid_address?({a, b, c, d}) do
    Enum.all?([a, b, c, d], &integer_in_range?(&1, 0, 0xFF))
  end

  defp valid_address?({a, b, c, d, e, f, g, h}) do
    Enum.all?([a, b, c, d, e, f, g, h], &integer_in_range?(&1, 0, 0xFFFF))
  end

  defp valid_address?(_address), do: false

  defp integer_in_range?(value, minimum, maximum) do
    is_integer(value) and value >= minimum and value <= maximum
  end

  defp blocked_address_reason({100, 100, 100, 200}), do: :cloud_metadata

  defp blocked_address_reason({_a, _b, _c, _d} = address) do
    range_reason(address, @ipv4_special_ranges)
  end

  defp blocked_address_reason({0xFD00, 0x0EC2, 0, 0, 0, 0, 0, 0x0254}),
    do: :cloud_metadata

  defp blocked_address_reason({_a, _b, _c, _d, _e, _f, _g, _h} = address) do
    case range_reason(address, @ipv6_special_ranges) do
      nil -> if address_in_range?(address, @ipv6_global_unicast), do: nil, else: :non_global
      reason -> reason
    end
  end

  defp blocked_address_reason(_address), do: nil

  defp range_reason(address, ranges) do
    Enum.find_value(ranges, fn {prefix, prefix_length, reason} ->
      if address_in_range?(address, {prefix, prefix_length}), do: reason
    end)
  end

  defp address_in_range?(address, {prefix, prefix_length}) do
    {address_value, bit_count} = address_integer(address)
    {prefix_value, ^bit_count} = address_integer(prefix)
    shift = bit_count - prefix_length
    bsr(address_value, shift) == bsr(prefix_value, shift)
  end

  defp address_integer({_a, _b, _c, _d} = address) do
    {join_address_parts(Tuple.to_list(address), 8), 32}
  end

  defp address_integer({_a, _b, _c, _d, _e, _f, _g, _h} = address) do
    {join_address_parts(Tuple.to_list(address), 16), 128}
  end

  defp join_address_parts(parts, part_bits) do
    Enum.reduce(parts, 0, fn part, value -> bsl(value, part_bits) + part end)
  end

  defp address_to_string(address) do
    address
    |> :inet.ntoa()
    |> to_string()
  end

  defp destination_policy_error(message, details) do
    {:error, Error.invalid_error(message, Map.put(details, :error_code, @policy_error_code))}
  end

  defp config(key, default) do
    :jido_browser
    |> Application.get_env(:web_fetch, [])
    |> Keyword.get(key, default)
  end
end
