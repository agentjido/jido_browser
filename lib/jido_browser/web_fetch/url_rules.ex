defmodule Jido.Browser.WebFetch.URLRules do
  @moduledoc false

  alias Jido.Browser.Error

  @default_max_url_length 2_048
  @policy_error_code :url_not_allowed

  @doc false
  @spec validate(String.t(), keyword()) :: {:ok, String.t(), URI.t()} | {:error, Exception.t()}
  def validate(url, opts) do
    normalized_url = String.trim(url)
    max_url_length = opts[:max_url_length] || @default_max_url_length

    with :ok <- validate_url_length(normalized_url, max_url_length),
         {:ok, uri} <- parse_fetch_uri(normalized_url),
         :ok <- validate_uri_host(uri) do
      {:ok, URI.to_string(uri), normalize_uri(uri)}
    end
  end

  @doc false
  @spec validate_known(String.t(), keyword()) :: :ok | {:error, Exception.t()}
  def validate_known(url, opts) do
    known_urls =
      opts[:known_urls]
      |> List.wrap()
      |> Enum.map(&normalize_known_url/1)
      |> Enum.reject(&is_nil/1)

    if Keyword.get(opts, :require_known_url, false) do
      if url in known_urls do
        :ok
      else
        {:error,
         Error.invalid_error("Web fetch URL must already be present in tool context", %{
           error_code: :url_not_allowed,
           url: url
         })}
      end
    else
      :ok
    end
  end

  @doc false
  @spec validate_domain_filters(URI.t(), keyword()) :: :ok | {:error, Exception.t()}
  def validate_domain_filters(%URI{} = uri, opts) do
    with {:ok, allowed_rules} <- normalize_domain_rules(opts[:allowed_domains]),
         {:ok, blocked_rules} <- normalize_domain_rules(opts[:blocked_domains]) do
      cond do
        allowed_rules != [] and not Enum.any?(allowed_rules, &rule_matches?(&1, uri)) ->
          {:error,
           Error.invalid_error("URL is not permitted by allowed_domains", %{
             error_code: :url_not_allowed,
             url: URI.to_string(uri)
           })}

        blocked_rules != [] and Enum.any?(blocked_rules, &rule_matches?(&1, uri)) ->
          {:error,
           Error.invalid_error("URL is blocked by blocked_domains", %{
             error_code: :url_not_allowed,
             url: URI.to_string(uri)
           })}

        true ->
          :ok
      end
    end
  end

  @doc false
  @spec resolve_redirect_url(String.t(), String.t(), keyword()) ::
          {:ok, String.t(), URI.t()} | {:error, Exception.t()}
  def resolve_redirect_url(current_url, location, opts) do
    case build_strict_redirect_url(current_url, location, opts) do
      {:ok, _redirect_url, _redirect_uri} = result ->
        result

      {:error, reason} ->
        invalid_redirect_error(current_url, {:rejected_location, location, reason})
    end
  rescue
    error ->
      invalid_redirect_error(current_url, {:invalid_location, location, error})
  end

  @doc false
  @spec normalize_final_url(map()) :: {:ok, String.t(), URI.t()} | {:error, Exception.t()}
  def normalize_final_url(%{final_url: final_url}) when is_binary(final_url) do
    with {:ok, uri} <- parse_fetch_uri(final_url),
         :ok <- validate_uri_host(uri) do
      normalized = normalize_uri(uri)
      {:ok, URI.to_string(normalized), normalized}
    end
  end

  def normalize_final_url(response) do
    {:error,
     Error.adapter_error("Web fetch backend returned an invalid final URL", %{
       error_code: :unavailable,
       response: response
     })}
  end

  @doc false
  @spec normalize_uri(URI.t()) :: URI.t()
  def normalize_uri(%URI{} = uri) do
    %{uri | host: String.downcase(uri.host || ""), fragment: nil}
  end

  defp build_strict_redirect_url(current_url, location, opts) do
    with :ok <- validate_redirect_text(location),
         {:ok, reference} <- URI.new(location),
         :ok <- validate_redirect_reference(reference, location),
         merged_uri = URI.merge(URI.parse(current_url), reference),
         :ok <- validate_redirect_target_uri(merged_uri),
         normalized_uri = normalize_uri(merged_uri),
         redirect_url = URI.to_string(normalized_uri),
         :ok <- validate_redirect_url_length(redirect_url, opts) do
      {:ok, redirect_url, normalized_uri}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_redirect_text(location) do
    cond do
      location == "" -> {:error, :missing_location}
      forbidden_redirect_byte?(location) -> {:error, :forbidden_character}
      not valid_percent_escapes?(location) -> {:error, :invalid_percent_escape}
      true -> :ok
    end
  end

  defp forbidden_redirect_byte?(location) do
    location
    |> :binary.bin_to_list()
    |> Enum.any?(fn byte -> byte <= 0x20 or byte == 0x7F or byte == ?\\ end)
  end

  defp valid_percent_escapes?(<<>>), do: true

  defp valid_percent_escapes?(<<?%, high, low, rest::binary>>) do
    case {hex_value(high), hex_value(low)} do
      {{:ok, high_value}, {:ok, low_value}} ->
        decoded = high_value * 16 + low_value
        decoded > 0x1F and decoded != 0x7F and valid_percent_escapes?(rest)

      _other ->
        false
    end
  end

  defp valid_percent_escapes?(<<?%, _rest::binary>>), do: false
  defp valid_percent_escapes?(<<_byte, rest::binary>>), do: valid_percent_escapes?(rest)

  defp hex_value(value) when value in ?0..?9, do: {:ok, value - ?0}
  defp hex_value(value) when value in ?A..?F, do: {:ok, value - ?A + 10}
  defp hex_value(value) when value in ?a..?f, do: {:ok, value - ?a + 10}
  defp hex_value(_value), do: :error

  defp validate_redirect_reference(%URI{} = uri, location) do
    with :ok <- validate_redirect_scheme(uri.scheme, allow_relative?: true),
         :ok <- validate_redirect_userinfo(uri.userinfo),
         :ok <- validate_redirect_authority(uri, location),
         :ok <- validate_optional_redirect_host(uri.host),
         :ok <- validate_redirect_port(uri.port) do
      validate_redirect_path(uri.host, uri.path)
    end
  end

  defp validate_redirect_target_uri(%URI{} = uri) do
    with :ok <- validate_redirect_scheme(uri.scheme, allow_relative?: false),
         :ok <- validate_redirect_userinfo(uri.userinfo),
         :ok <- validate_required_redirect_host(uri.host),
         :ok <- validate_redirect_port(uri.port) do
      validate_redirect_path(uri.host, uri.path)
    end
  end

  defp validate_redirect_scheme(nil, allow_relative?: true), do: :ok

  defp validate_redirect_scheme(scheme, allow_relative?: _allow_relative) do
    if String.downcase(scheme || "") in ["http", "https"], do: :ok, else: {:error, :unsupported_scheme}
  end

  defp validate_redirect_userinfo(nil), do: :ok
  defp validate_redirect_userinfo(_userinfo), do: {:error, :userinfo_not_allowed}

  defp validate_redirect_authority(%URI{scheme: scheme, host: host}, location) do
    if (String.starts_with?(location, "//") or not is_nil(scheme)) and host in [nil, ""],
      do: {:error, :missing_host},
      else: :ok
  end

  defp validate_optional_redirect_host(nil), do: :ok
  defp validate_optional_redirect_host(host), do: validate_required_redirect_host(host)

  defp validate_required_redirect_host(host) when host in [nil, ""], do: {:error, :missing_host}

  defp validate_required_redirect_host(host) do
    if valid_redirect_host?(host), do: :ok, else: {:error, :invalid_host}
  end

  defp validate_redirect_port(nil), do: :ok
  defp validate_redirect_port(port) when port in 1..65_535, do: :ok
  defp validate_redirect_port(_port), do: {:error, :invalid_port}

  defp validate_redirect_path(nil, _path), do: :ok
  defp validate_redirect_path(_host, nil), do: :ok

  defp validate_redirect_path(_host, path) do
    if String.starts_with?(path, "/"), do: :ok, else: {:error, :invalid_path}
  end

  defp valid_redirect_host?(host) do
    case :inet.parse_address(String.to_charlist(host)) do
      {:ok, _address} -> true
      {:error, :einval} -> valid_dns_hostname?(host)
    end
  end

  defp valid_dns_hostname?(host) do
    trimmed_host = String.trim_trailing(host, ".")
    labels = String.split(trimmed_host, ".", trim: false)

    byte_size(host) <= 253 and ascii_only?(host) and trimmed_host != "" and
      Enum.all?(labels, fn label ->
        byte_size(label) in 1..63 and
          String.match?(label, ~r/\A[a-zA-Z0-9](?:[a-zA-Z0-9-]*[a-zA-Z0-9])?\z/)
      end)
  end

  defp validate_redirect_url_length(url, opts) do
    if String.length(url) <= (opts[:max_url_length] || @default_max_url_length),
      do: :ok,
      else: {:error, :url_too_long}
  end

  defp invalid_redirect_error(current_url, reason) do
    destination_policy_error("Web fetch redirect location is not allowed", %{
      url: current_url,
      reason: reason
    })
  end

  defp normalize_domain_rules(nil), do: {:ok, []}

  defp normalize_domain_rules(rules) do
    rules
    |> List.wrap()
    |> Enum.reduce_while({:ok, []}, fn rule, {:ok, acc} ->
      case normalize_domain_rule(rule) do
        {:ok, normalized} -> {:cont, {:ok, [normalized | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, normalized} -> {:ok, Enum.reverse(normalized)}
      error -> error
    end
  end

  defp normalize_domain_rule(rule) when is_binary(rule) do
    normalized = String.trim(rule)

    cond do
      normalized == "" ->
        {:error, Error.invalid_error("Domain rules cannot be empty", %{error_code: :invalid_input})}

      String.contains?(normalized, "://") ->
        {:error,
         Error.invalid_error("Domain rules must not include URL schemes", %{
           error_code: :invalid_input,
           rule: normalized
         })}

      true ->
        uri = URI.parse("https://" <> normalized)
        host = String.downcase(uri.host || "")
        path = uri.path || "/"

        cond do
          host == "" ->
            {:error,
             Error.invalid_error("Domain rule must include a host", %{error_code: :invalid_input, rule: normalized})}

          not ascii_only?(host) ->
            {:error,
             Error.invalid_error("Domain rules must use ASCII hosts", %{
               error_code: :invalid_input,
               rule: normalized
             })}

          true ->
            {:ok, %{host: host, path: normalize_rule_path(path)}}
        end
    end
  end

  defp normalize_domain_rule(rule) do
    {:error, Error.invalid_error("Domain rule must be a string", %{error_code: :invalid_input, rule: rule})}
  end

  defp rule_matches?(%{host: host, path: path}, %URI{host: uri_host} = uri) do
    uri_host = String.downcase(uri_host)
    request_path = normalize_rule_path(uri.path || "/")

    host_matches? = uri_host == host or String.ends_with?(uri_host, "." <> host)
    path_matches? = path == "/" or String.starts_with?(request_path, path)

    host_matches? and path_matches?
  end

  defp validate_url_length("", _max_url_length) do
    {:error, Error.invalid_error("URL cannot be empty", %{error_code: :invalid_input})}
  end

  defp validate_url_length(normalized_url, max_url_length) do
    if String.length(normalized_url) > max_url_length do
      {:error,
       Error.invalid_error("URL exceeds maximum length", %{
         error_code: :url_too_long,
         max_url_length: max_url_length
       })}
    else
      :ok
    end
  end

  defp parse_fetch_uri(normalized_url) do
    uri = URI.parse(normalized_url)

    if uri.scheme in ["http", "https"] do
      {:ok, uri}
    else
      {:error,
       Error.invalid_error("Web fetch only supports http and https URLs", %{
         error_code: :invalid_input,
         scheme: uri.scheme
       })}
    end
  end

  defp validate_uri_host(%URI{host: host}) when host in [nil, ""] do
    {:error, Error.invalid_error("URL must include a host", %{error_code: :invalid_input})}
  end

  defp validate_uri_host(%URI{host: host}) do
    if ascii_only?(host) do
      :ok
    else
      {:error,
       Error.invalid_error("Web fetch only accepts ASCII hostnames", %{
         error_code: :url_not_allowed,
         host: host
       })}
    end
  end

  defp normalize_known_url(url) when is_binary(url) do
    url
    |> String.trim()
    |> case do
      "" -> nil
      value -> value
    end
  end

  defp normalize_known_url(_), do: nil

  defp normalize_rule_path(""), do: "/"
  defp normalize_rule_path(path), do: if(String.starts_with?(path, "/"), do: path, else: "/" <> path)

  defp ascii_only?(value) when is_binary(value) do
    String.printable?(value) and String.match?(value, ~r/^[\x00-\x7F]+$/)
  end

  @doc false
  @spec destination_policy_error(String.t(), map()) :: {:error, Exception.t()}
  def destination_policy_error(message, details) do
    {:error, Error.invalid_error(message, Map.put(details, :error_code, @policy_error_code))}
  end
end
