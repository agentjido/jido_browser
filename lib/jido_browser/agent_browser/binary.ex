defmodule Jido.Browser.AgentBrowser.Binary do
  @moduledoc false

  alias Jido.Browser.Error

  @supported_version "0.35.1"
  @binary_name "agent-browser"

  @type source :: :configured | :package | :path

  @doc false
  @spec supported_version() :: String.t()
  def supported_version, do: @supported_version

  @doc false
  @spec resolve(String.t(), keyword()) :: {:ok, String.t()} | {:error, Error.AdapterError.t()}
  def resolve(package_path, opts \\ []) when is_binary(package_path) do
    configured_path = Keyword.get_lazy(opts, :configured_path, &configured_path/0)

    case configured_path do
      nil -> resolve_candidates(package_path, opts)
      "" -> resolve_candidates(package_path, opts)
      path when is_binary(path) -> validate(path, :configured)
      path -> {:error, invalid_configured_path_error(path)}
    end
  end

  @doc false
  @spec validate(String.t(), source()) :: {:ok, String.t()} | {:error, Error.AdapterError.t()}
  def validate(path, source) when is_binary(path) do
    with :ok <- validate_file(path, source),
         :ok <- ensure_supported_version(path) do
      {:ok, path}
    else
      {:error, %Error.AdapterError{} = error} -> {:error, add_source(error, path, source)}
    end
  end

  @doc false
  @spec ensure_supported_version(String.t()) :: :ok | {:error, Error.AdapterError.t()}
  def ensure_supported_version(binary) do
    case System.cmd(binary, ["--version"], stderr_to_stdout: true) do
      {output, 0} ->
        case parse_version(output) do
          {:ok, @supported_version} ->
            :ok

          {:ok, version} ->
            {:error,
             Error.adapter_error("Unsupported agent-browser version", %{
               supported: @supported_version,
               detected: version
             })}

          {:error, reason} ->
            {:error, Error.adapter_error("Could not parse agent-browser version", %{reason: reason})}
        end

      {output, code} ->
        {:error,
         Error.adapter_error("Failed to inspect agent-browser version", %{
           exit_status: code,
           output: String.trim(output)
         })}
    end
  rescue
    error ->
      {:error, Error.adapter_error("Failed to inspect agent-browser version", %{reason: Exception.message(error)})}
  end

  @doc false
  @spec parse_version(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def parse_version(output) do
    case Regex.run(~r/agent-browser\s+(\d+\.\d+\.\d+)/, output, capture: :all_but_first) do
      [version] -> {:ok, version}
      _ -> {:error, String.trim(output)}
    end
  end

  defp resolve_candidates(package_path, opts) do
    if File.exists?(package_path) do
      case validate(package_path, :package) do
        {:ok, _path} = result -> result
        {:error, error} -> resolve_path_candidate(opts, error)
      end
    else
      resolve_path_candidate(opts, nil)
    end
  end

  defp resolve_path_candidate(opts, package_error) do
    path_binary = Keyword.get_lazy(opts, :path_binary, fn -> System.find_executable(@binary_name) end)

    case path_binary do
      nil -> {:error, package_error || binary_not_found_error()}
      "" -> {:error, package_error || binary_not_found_error()}
      path when is_binary(path) -> validate(path, :path)
      path -> {:error, invalid_path_candidate_error(path)}
    end
  end

  defp validate_file(path, source) do
    case File.stat(path) do
      {:ok, %File.Stat{type: :regular} = stat} ->
        if executable?(path, stat) do
          :ok
        else
          {:error,
           Error.adapter_error("#{source_label(source)} agent-browser binary is not executable", %{
             path: path,
             source: source
           })}
        end

      {:ok, _stat} ->
        {:error,
         Error.adapter_error("#{source_label(source)} agent-browser binary is not a regular file", %{
           path: path,
           source: source
         })}

      {:error, :enoent} ->
        {:error,
         Error.adapter_error("#{source_label(source)} agent-browser binary was not found", %{
           path: path,
           source: source
         })}

      {:error, reason} ->
        {:error,
         Error.adapter_error("Could not inspect #{source_label(source, :lower)} agent-browser binary", %{
           path: path,
           reason: reason,
           source: source
         })}
    end
  end

  defp executable?(path, stat) do
    case :os.type() do
      {:win32, _} -> String.downcase(Path.extname(path)) in [".exe", ".com", ".bat", ".cmd"]
      _ -> Bitwise.band(stat.mode, 0o111) != 0
    end
  end

  defp add_source(%{details: %{source: _existing_source}} = error, _path, _source), do: error

  defp add_source(error, path, source) do
    details = Map.merge(error.details, %{path: path, source: source})
    %{error | message: "#{source_label(source)} agent-browser binary: #{error.message}", details: details}
  end

  defp configured_path do
    :jido_browser
    |> Application.get_env(:agent_browser, [])
    |> Keyword.get(:binary_path)
  end

  defp invalid_configured_path_error(path) do
    Error.adapter_error("Configured agent-browser binary path must be a non-empty string", %{
      path: path,
      source: :configured
    })
  end

  defp invalid_path_candidate_error(path) do
    Error.adapter_error("PATH agent-browser binary path must be a string", %{path: path, source: :path})
  end

  defp binary_not_found_error do
    Error.adapter_error("agent-browser binary not found. Install with: mix jido_browser.install agent_browser", %{
      supported: @supported_version
    })
  end

  defp source_label(:configured), do: "Configured"
  defp source_label(:package), do: "Packaged"
  defp source_label(:path), do: "PATH"

  defp source_label(source, :lower), do: source |> source_label() |> String.downcase()
end
