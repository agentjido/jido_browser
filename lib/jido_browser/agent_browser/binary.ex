defmodule Jido.Browser.AgentBrowser.Binary do
  @moduledoc false

  alias Jido.Browser.Error

  @supported_version "0.35.1"

  @doc false
  @spec supported_version() :: String.t()
  def supported_version, do: @supported_version

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
end
