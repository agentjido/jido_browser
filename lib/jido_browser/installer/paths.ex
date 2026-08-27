defmodule Jido.Browser.Installer.Paths do
  @moduledoc false

  @type platform :: :darwin_arm64 | :darwin_amd64 | :linux_amd64 | :linux_arm64 | :windows_amd64

  @doc false
  @spec target() :: platform()
  def target do
    os = detect_os()
    arch = detect_arch()
    :"#{os}_#{arch}"
  end

  @doc false
  @spec default_install_path() :: String.t()
  def default_install_path do
    if path = Application.get_env(:jido_browser, :path) do
      Path.expand(path)
    else
      Path.join(Path.dirname(Mix.Project.build_path()), "jido_browser-#{target()}")
    end
  end

  @doc false
  @spec agent_browser_package_path() :: String.t()
  def agent_browser_package_path do
    Path.join(default_install_path(), agent_browser_binary_name())
  end

  @doc false
  @spec agent_browser_binary_name() :: String.t()
  def agent_browser_binary_name do
    case target() do
      :darwin_arm64 -> "agent-browser-darwin-arm64"
      :darwin_amd64 -> "agent-browser-darwin-x64"
      :linux_amd64 -> "agent-browser-linux-x64"
      :linux_arm64 -> "agent-browser-linux-arm64"
      :windows_amd64 -> "agent-browser-win32-x64.exe"
    end
  end

  defp detect_os do
    case :os.type() do
      {:unix, :darwin} -> :darwin
      {:unix, :linux} -> :linux
      {:win32, _} -> :windows
      other -> other
    end
  end

  defp detect_arch do
    :erlang.system_info(:system_architecture)
    |> to_string()
    |> parse_arch()
  end

  defp parse_arch("aarch64" <> _), do: :arm64
  defp parse_arch("arm64" <> _), do: :arm64
  defp parse_arch("x86_64" <> _), do: :amd64
  defp parse_arch("amd64" <> _), do: :amd64
  defp parse_arch("win32" <> _), do: :amd64
  defp parse_arch(_other), do: :amd64
end
