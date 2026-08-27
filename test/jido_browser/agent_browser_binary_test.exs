defmodule Jido.Browser.AgentBrowserBinaryTest do
  use ExUnit.Case, async: false

  alias Jido.Browser.AgentBrowser.Binary
  alias Jido.Browser.AgentBrowser.Runtime
  alias Jido.Browser.Installer

  describe "supported version contract" do
    test "is shared by the binary, runtime, and installer" do
      assert Binary.supported_version() == "0.35.1"
      assert Runtime.supported_version() == Binary.supported_version()
      assert Installer.configured_version(:agent_browser) == Binary.supported_version()
    end

    test "does not allow the installer version to differ from the runtime version" do
      previous = Application.get_env(:jido_browser, :agent_browser_version, :not_set)
      Application.put_env(:jido_browser, :agent_browser_version, "0.30.0")

      try do
        assert Installer.configured_version(:agent_browser) == Binary.supported_version()
      after
        restore_env(:agent_browser_version, previous)
      end
    end
  end

  describe "version validation" do
    test "accepts the supported version" do
      with_binary("agent-browser 0.35.1", fn binary ->
        assert :ok = Binary.ensure_supported_version(binary)
      end)
    end

    test "rejects an incompatible version" do
      with_binary("agent-browser 0.34.0", fn binary ->
        assert {:error, error} = Binary.ensure_supported_version(binary)
        assert Exception.message(error) == "Unsupported agent-browser version"
        assert error.details.detected == "0.34.0"
        assert error.details.supported == "0.35.1"
      end)
    end

    test "rejects an unparsable version" do
      with_binary("unknown version", fn binary ->
        assert {:error, error} = Binary.ensure_supported_version(binary)
        assert Exception.message(error) == "Could not parse agent-browser version"
        assert error.details.reason == "unknown version"
      end)
    end
  end

  describe "binary resolution" do
    test "uses a compatible configured binary before package and PATH binaries" do
      with_binary_directory(fn directory ->
        configured = write_binary(directory, "configured", "agent-browser 0.35.1")
        package = write_binary(directory, "package", "agent-browser 0.35.1")
        path = write_binary(directory, "path", "agent-browser 0.35.1")

        assert {:ok, ^configured} =
                 Binary.resolve(package, configured_path: configured, path_binary: path)
      end)
    end

    test "does not fall through when a configured binary is missing" do
      with_binary_directory(fn directory ->
        missing = Path.join(directory, "missing")
        package = write_binary(directory, "package", "agent-browser 0.35.1")
        path = write_binary(directory, "path", "agent-browser 0.35.1")

        assert {:error, error} =
                 Binary.resolve(package, configured_path: missing, path_binary: path)

        assert Exception.message(error) == "Configured agent-browser binary was not found"
        assert error.details.path == missing
      end)
    end

    test "does not fall through when a configured binary is not executable" do
      with_binary_directory(fn directory ->
        configured = write_binary(directory, "configured", "agent-browser 0.35.1", 0o644)
        package = write_binary(directory, "package", "agent-browser 0.35.1")
        path = write_binary(directory, "path", "agent-browser 0.35.1")

        assert {:error, error} =
                 Binary.resolve(package, configured_path: configured, path_binary: path)

        assert Exception.message(error) == "Configured agent-browser binary is not executable"
      end)
    end

    test "does not fall through when a configured binary version is unparsable" do
      with_binary_directory(fn directory ->
        configured = write_binary(directory, "configured", "unknown version")
        package = write_binary(directory, "package", "agent-browser 0.35.1")
        path = write_binary(directory, "path", "agent-browser 0.35.1")

        assert {:error, error} =
                 Binary.resolve(package, configured_path: configured, path_binary: path)

        assert Exception.message(error) ==
                 "Configured agent-browser binary: Could not parse agent-browser version"
      end)
    end

    test "does not fall through when a configured binary version is incompatible" do
      with_binary_directory(fn directory ->
        configured = write_binary(directory, "configured", "agent-browser 0.34.0")
        package = write_binary(directory, "package", "agent-browser 0.35.1")
        path = write_binary(directory, "path", "agent-browser 0.35.1")

        assert {:error, error} =
                 Binary.resolve(package, configured_path: configured, path_binary: path)

        assert Exception.message(error) ==
                 "Configured agent-browser binary: Unsupported agent-browser version"
      end)
    end

    test "uses a compatible package binary before an incompatible PATH binary" do
      with_binary_directory(fn directory ->
        package = write_binary(directory, "package", "agent-browser 0.35.1")
        path = write_binary(directory, "path", "agent-browser 0.34.0")

        assert {:ok, ^package} =
                 Binary.resolve(package, configured_path: nil, path_binary: path)
      end)
    end

    test "uses a compatible PATH binary when the package binary is incompatible" do
      with_binary_directory(fn directory ->
        package = write_binary(directory, "package", "agent-browser 0.34.0")
        path = write_binary(directory, "path", "agent-browser 0.35.1")

        assert {:ok, ^path} =
                 Binary.resolve(package, configured_path: nil, path_binary: path)
      end)
    end

    test "returns a clear error when no candidate exists" do
      with_binary_directory(fn directory ->
        package = Path.join(directory, "missing-package")

        assert {:error, error} =
                 Binary.resolve(package, configured_path: nil, path_binary: nil)

        assert Exception.message(error) =~ "agent-browser binary not found"
        assert error.details.supported == "0.35.1"
      end)
    end
  end

  describe "runtime and installer resolution" do
    test "both prefer the compatible package binary over an incompatible PATH binary" do
      with_binary_directory(fn directory ->
        package_directory = Path.join(directory, "package")
        path_directory = Path.join(directory, "path")

        with_env(:path, package_directory, fn ->
          package = write_binary_path(Installer.agent_browser_package_path(), "agent-browser 0.35.1")
          _path = write_binary(path_directory, "agent-browser", "agent-browser 0.34.0")

          with_system_path(path_directory, fn ->
            with_agent_browser_config([], fn ->
              assert {:ok, ^package} = Runtime.find_binary()
              assert Installer.bin_path(:agent_browser) == package
              assert Installer.installed?(:agent_browser)
            end)
          end)
        end)
      end)
    end

    test "installer returns a configured-path error without installing another binary" do
      with_binary_directory(fn directory ->
        missing = Path.join(directory, "missing-configured")

        with_agent_browser_config([binary_path: missing], fn ->
          assert {:error, error} = Installer.ensure_installed(adapter: :agent_browser)
          assert Exception.message(error) == "Configured agent-browser binary was not found"

          assert {:error, install_error} =
                   Installer.install(:agent_browser, path: Path.join(directory, "install-target"))

          assert Exception.message(install_error) == "Configured agent-browser binary was not found"
          refute File.exists?(Path.join(directory, "install-target"))
          refute Installer.installed?(:agent_browser)
          assert is_nil(Installer.bin_path(:agent_browser))
        end)
      end)
    end
  end

  defp with_binary(version_output, fun) do
    with_binary_directory(fn directory ->
      fun.(write_binary(directory, "agent-browser", version_output))
    end)
  end

  defp with_binary_directory(fun) do
    directory = Path.join(System.tmp_dir!(), "jido_browser_binary_#{System.unique_integer([:positive])}")
    File.mkdir_p!(directory)

    try do
      fun.(directory)
    after
      File.rm_rf!(directory)
    end
  end

  defp write_binary(directory, name, version_output, mode \\ 0o755) do
    write_binary_path(Path.join(directory, name), version_output, mode)
  end

  defp write_binary_path(path, version_output, mode \\ 0o755) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, "#!/bin/sh\nprintf '%s\\n' '#{version_output}'\n")
    File.chmod!(path, mode)
    path
  end

  defp with_agent_browser_config(config, fun) do
    previous = Application.get_env(:jido_browser, :agent_browser, :not_set)
    Application.put_env(:jido_browser, :agent_browser, config)

    try do
      fun.()
    after
      restore_env(:agent_browser, previous)
    end
  end

  defp with_env(key, value, fun) do
    previous = Application.get_env(:jido_browser, key, :not_set)
    Application.put_env(:jido_browser, key, value)

    try do
      fun.()
    after
      restore_env(key, previous)
    end
  end

  defp with_system_path(directory, fun) do
    previous = System.get_env("PATH")
    System.put_env("PATH", directory)

    try do
      fun.()
    after
      if previous, do: System.put_env("PATH", previous), else: System.delete_env("PATH")
    end
  end

  defp restore_env(key, :not_set), do: Application.delete_env(:jido_browser, key)
  defp restore_env(key, value), do: Application.put_env(:jido_browser, key, value)
end
