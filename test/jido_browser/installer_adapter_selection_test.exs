defmodule Jido.Browser.InstallerAdapterSelectionTest do
  use ExUnit.Case, async: false

  alias Jido.Browser.Adapters.AgentBrowser
  alias Jido.Browser.Adapters.Lightpanda
  alias Jido.Browser.Adapters.Vibium
  alias Jido.Browser.Installer

  @config_keys [:adapter, :agent_browser, :lightpanda, :vibium]

  setup do
    previous = Map.new(@config_keys, &{&1, Application.get_env(:jido_browser, &1, :__missing__)})
    path = temporary_browser_command()

    on_exit(fn ->
      Enum.each(previous, fn
        {key, :__missing__} -> Application.delete_env(:jido_browser, key)
        {key, value} -> Application.put_env(:jido_browser, key, value)
      end)

      File.rm_rf(Path.dirname(path))
    end)

    {:ok, path: path}
  end

  test "configured adapter modules keep their installer target", %{path: path} do
    cases = [
      {AgentBrowser, :agent_browser},
      {Lightpanda, :lightpanda},
      {Vibium, :vibium}
    ]

    Enum.each(cases, fn {adapter, config_key} ->
      set_missing_adapter_paths()
      Application.put_env(:jido_browser, :adapter, adapter)
      Application.put_env(:jido_browser, config_key, binary_path: path)

      assert :ok = Installer.ensure_installed()
    end)
  end

  test "unknown configured adapters keep the AgentBrowser installer default", %{path: path} do
    set_missing_adapter_paths()
    Application.put_env(:jido_browser, :adapter, __MODULE__)
    Application.put_env(:jido_browser, :agent_browser, binary_path: path)

    assert :ok = Installer.ensure_installed()
  end

  defp set_missing_adapter_paths do
    missing = Path.join(System.tmp_dir!(), "jido_browser_missing_#{System.unique_integer([:positive])}")

    for key <- [:agent_browser, :lightpanda, :vibium] do
      Application.put_env(:jido_browser, key, binary_path: missing)
    end
  end

  defp temporary_browser_command do
    directory = Path.join(System.tmp_dir!(), "jido_browser_selection_#{System.unique_integer([:positive])}")
    path = Path.join(directory, "browser-command")
    File.mkdir_p!(directory)

    File.write!(
      path,
      "#!/bin/sh\nif [ \"$1\" = \"--version\" ]; then printf 'agent-browser 0.35.1\\n'; fi\nexit 0\n"
    )

    File.chmod!(path, 0o755)
    path
  end
end
