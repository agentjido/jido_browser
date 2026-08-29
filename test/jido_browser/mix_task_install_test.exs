defmodule Jido.Browser.MixTaskInstallTest do
  use ExUnit.Case, async: false
  use Mimic

  alias Jido.Browser.Error
  alias Jido.Browser.Installer
  alias Mix.Tasks.JidoBrowser.Install, as: InstallTask

  setup :set_mimic_global

  setup_all do
    Mimic.copy(Installer)
    :ok
  end

  setup do
    directory =
      Path.join(System.tmp_dir!(), "jido_browser_mix_task_#{System.unique_integer([:positive])}")

    File.mkdir_p!(directory)
    on_exit(fn -> File.rm_rf!(directory) end)
    {:ok, directory: directory}
  end

  test "accepts every supported target name and the agent-browser alias" do
    targets = [
      {"agent_browser", :agent_browser},
      {"agent-browser", :agent_browser},
      {"vibium", :vibium},
      {"lightpanda", :lightpanda}
    ]

    Enum.each(targets, fn {name, target} ->
      expect(Installer, :installed?, fn ^target -> true end)
      expect(Installer, :bin_path, fn ^target -> "/fake/#{target}" end)

      assert :ok = InstallTask.run(["--if-missing", name])
    end)
  end

  test "raises for unknown input without creating an atom" do
    name = "unknown_target_#{System.unique_integer([:positive])}"

    assert_raise ArgumentError, fn -> String.to_existing_atom(name) end

    assert_raise Mix.Error,
                 "Unknown binary: #{name}. Use 'agent_browser', 'vibium', or 'lightpanda'.",
                 fn -> InstallTask.run([name]) end

    assert_raise ArgumentError, fn -> String.to_existing_atom(name) end
  end

  test "rejects the removed Web installer target" do
    assert_raise Mix.Error,
                 "Unknown binary: web. Use 'agent_browser', 'vibium', or 'lightpanda'.",
                 fn -> InstallTask.run(["web"]) end
  end

  test "raises with the target-specific reason for every failed installer" do
    failures = [
      {:agent_browser, Error.adapter_error("fake AgentBrowser failure")},
      {:vibium, {:npm_exit, 17}},
      {:lightpanda, "fake Lightpanda failure"}
    ]

    Enum.each(failures, fn {target, reason} ->
      expect(Installer, :installed?, fn ^target -> false end)

      expect(Installer, :install, fn ^target, opts ->
        assert opts == [force: false]
        {:error, reason}
      end)

      expected = "Failed to install #{target}: #{failure_message(reason)}"

      assert_raise Mix.Error, expected, fn ->
        InstallTask.run([Atom.to_string(target)])
      end
    end)
  end

  test "keeps successful installation behavior" do
    expect(Installer, :installed?, fn :vibium -> false end)

    expect(Installer, :install, fn :vibium, opts ->
      assert opts == [path: "/fake/install", force: true]
      :ok
    end)

    assert :ok = InstallTask.run(["--path", "/fake/install", "--force", "vibium"])
  end

  test "a failed installation command exits with a nonzero status", %{directory: directory} do
    missing = Path.join(directory, "missing-agent-browser")

    expression = """
    Application.put_env(:jido_browser, :agent_browser, binary_path: #{inspect(missing)})
    Mix.Task.run("jido_browser.install", ["agent_browser"])
    """

    {output, status} =
      System.cmd(
        System.find_executable("mix"),
        ["run", "--no-compile", "--no-start", "-e", expression],
        cd: File.cwd!(),
        env: [{"MIX_ENV", "test"}],
        stderr_to_stdout: true
      )

    assert status != 0
    assert output =~ "Failed to install agent_browser: Configured agent-browser binary was not found"
  end

  defp failure_message(%{__exception__: true} = reason), do: Exception.message(reason)
  defp failure_message(reason) when is_binary(reason), do: reason
  defp failure_message(reason), do: inspect(reason)
end
