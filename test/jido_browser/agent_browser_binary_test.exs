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

  defp with_binary(version_output, fun) do
    directory = Path.join(System.tmp_dir!(), "jido_browser_binary_#{System.unique_integer([:positive])}")
    binary = Path.join(directory, "agent-browser")

    File.mkdir_p!(directory)
    File.write!(binary, "#!/bin/sh\nprintf '%s\\n' '#{version_output}'\n")
    File.chmod!(binary, 0o755)

    try do
      fun.(binary)
    after
      File.rm_rf!(directory)
    end
  end

  defp restore_env(key, :not_set), do: Application.delete_env(:jido_browser, key)
  defp restore_env(key, value), do: Application.put_env(:jido_browser, key, value)
end
