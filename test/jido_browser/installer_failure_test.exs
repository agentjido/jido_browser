defmodule Jido.Browser.InstallerFailureTest do
  use ExUnit.Case, async: false
  use Mimic

  alias Jido.Browser.Installer

  setup :set_mimic_global

  setup_all do
    Mimic.copy(:httpc)
    :ok
  end

  setup do
    directory =
      Path.join(System.tmp_dir!(), "jido_browser_installer_#{System.unique_integer([:positive])}")

    File.mkdir_p!(directory)
    on_exit(fn -> File.rm_rf!(directory) end)
    {:ok, directory: directory}
  end

  describe "installed?/1" do
    test "rejects present command shims that return a failure", %{directory: directory} do
      Enum.each([:vibium, :web, :lightpanda], fn target ->
        path = write_command(Path.join(directory, Atom.to_string(target)), "exit 19")

        with_app_env(:jido_browser, target, [binary_path: path], fn ->
          assert Installer.bin_path(target) == path
          refute Installer.installed?(target)
        end)
      end)
    end

    test "accepts usable commands for all non-AgentBrowser targets", %{directory: directory} do
      probes = %{vibium: "version", web: "--help", lightpanda: "version"}

      Enum.each(probes, fn {target, probe} ->
        marker = Path.join(directory, "#{target}-probe")

        path =
          write_command(
            Path.join(directory, Atom.to_string(target)),
            exact_argument_command(probe, marker)
          )

        with_app_env(:jido_browser, target, [binary_path: path], fn ->
          assert Installer.bin_path(target) == path
          assert Installer.installed?(target)
          assert File.read!(marker) == probe
        end)
      end)
    end
  end

  describe "AgentBrowser installation" do
    test "propagates browser-install failure and removes the staged binary", %{directory: directory} do
      body = """
      #!/bin/sh
      case "$1" in
        --version) printf 'agent-browser 0.35.1\\n'; exit 0 ;;
        install) printf 'fake runtime failure\\n'; exit 27 ;;
      esac
      exit 2
      """

      expect_http_download(body)

      assert {:error, reason} = Installer.install(:agent_browser, path: directory)
      assert reason =~ "agent-browser install failed (exit 27)"
      assert reason =~ "fake runtime failure"

      target = Path.join(directory, agent_browser_binary_name())
      refute File.exists?(target)
      refute File.exists?(target <> ".tmp")
    end

    test "promotes a staged binary after browser installation succeeds", %{directory: directory} do
      body = """
      #!/bin/sh
      case "$1" in
        --version) printf 'agent-browser 0.35.1\\n'; exit 0 ;;
        install) exit 0 ;;
      esac
      exit 2
      """

      expect_http_download(body)

      assert :ok = Installer.install(:agent_browser, path: directory)

      target = Path.join(directory, agent_browser_binary_name())
      assert File.exists?(target)
      refute File.exists?(target <> ".tmp")
    end

    test "removes the staged binary when the install command cannot start", %{directory: directory} do
      body = """
      #!/bin/sh
      case "$1" in
        --version)
          /bin/chmod 0644 "$0"
          printf 'agent-browser 0.35.1\\n'
          exit 0
          ;;
      esac
      exit 2
      """

      expect_http_download(body)

      assert {:error, reason} = Installer.install(:agent_browser, path: directory)
      assert reason =~ "agent-browser install failed"
      assert reason =~ ":eacces"

      target = Path.join(directory, agent_browser_binary_name())
      refute File.exists?(target)
      refute File.exists?(target <> ".tmp")
    end
  end

  describe "Web installation" do
    test "propagates download failure and removes the staged binary", %{directory: directory} do
      expect(:httpc, :request, fn :get, {_url, []}, _http_options, body_format: :binary ->
        {:error, :fake_offline}
      end)

      assert {:error, "Download failed: :fake_offline"} = Installer.install(:web, path: directory)

      target = Path.join(directory, web_binary_name())
      refute File.exists?(target)
      refute File.exists?(target <> ".tmp")
    end

    test "rejects and removes an unusable downloaded command", %{directory: directory} do
      expect_http_download("#!/bin/sh\nexit 31\n")

      assert {:error, reason} = Installer.install(:web, path: directory)
      assert reason =~ "downloaded web binary is not usable"

      target = Path.join(directory, web_binary_name())
      refute File.exists?(target)
      refute File.exists?(target <> ".tmp")
    end

    test "promotes a usable downloaded command", %{directory: directory} do
      marker = Path.join(directory, "web-download-probe")
      expect_http_download("#!/bin/sh\n#{exact_argument_command("--help", marker)}\n")

      assert :ok = Installer.install(:web, path: directory)

      target = Path.join(directory, web_binary_name())
      assert File.exists?(target)
      refute File.exists?(target <> ".tmp")
      assert File.read!(marker) == "--help"
    end

    test "rejects success when a configured broken command remains selected", %{directory: directory} do
      configured = write_command(Path.join(directory, "configured-web"), "exit 41")
      install_path = Path.join(directory, "web-install")
      expect_http_download("#!/bin/sh\nexit 0\n")

      with_app_env(:jido_browser, :web, [binary_path: configured], fn ->
        assert {:error, reason} = Installer.install(:web, path: install_path)
        assert reason =~ "web installation completed"
        assert reason =~ "selected executable is not usable at #{configured}"
        refute Installer.installed?(:web)
        assert command_succeeds?(Path.join(install_path, web_binary_name()), ["--help"])
      end)
    end
  end

  describe "Vibium installation" do
    test "propagates npm failure", %{directory: directory} do
      with_fake_vibium_install(directory, [npm_install_status: 17], fn _context ->
        assert {:error, reason} = Installer.install(:vibium)
        assert reason =~ "npm install failed (exit 17)"
      end)
    end

    test "propagates a missing staged command", %{directory: directory} do
      with_fake_vibium_install(directory, [source_type: :missing], fn context ->
        assert {:error, reason} = Installer.install(:vibium)
        assert reason =~ "Could not stage vibium binary after npm install"
        refute File.exists?(context.target)
        refute File.exists?(context.target <> ".tmp")
      end)
    end

    test "propagates a staged-command copy failure", %{directory: directory} do
      with_fake_vibium_install(directory, [source_type: :directory], fn context ->
        assert {:error, reason} = Installer.install(:vibium)
        assert reason =~ "Could not copy vibium binary"
        refute File.exists?(context.target)
        refute File.exists?(context.target <> ".tmp")
      end)
    end

    test "propagates browser-install failure and preserves an earlier target", %{directory: directory} do
      with_fake_vibium_install(directory, [browser_install_status: 29], fn context ->
        old_body = "#!/bin/sh\n# earlier target\nexit 0\n"
        write_command(context.target, "# earlier target\nexit 0")

        assert {:error, reason} = Installer.install(:vibium)
        assert reason =~ "vibium browser install failed (exit 29)"
        assert reason =~ "fake browser failure"
        assert File.read!(context.target) == old_body
        refute File.exists?(context.target <> ".tmp")
      end)
    end

    test "promotes the staged command after all steps succeed", %{directory: directory} do
      with_fake_vibium_install(directory, [], fn context ->
        assert :ok = Installer.install(:vibium)
        assert File.exists?(context.target)
        refute File.exists?(context.target <> ".tmp")
        assert Installer.installed?(:vibium)
      end)
    end

    test "rejects success when a configured broken command remains selected", %{directory: directory} do
      with_fake_vibium_install(directory, [], fn context ->
        configured = write_command(Path.join(directory, "configured-vibium"), "exit 43")

        with_app_env(:jido_browser, :vibium, [binary_path: configured], fn ->
          assert {:error, reason} = Installer.install(:vibium)
          assert reason =~ "vibium installation completed"
          assert reason =~ "selected executable is not usable at #{configured}"
          refute Installer.installed?(:vibium)
          assert command_succeeds?(context.target, ["version"])
        end)
      end)
    end
  end

  describe "Lightpanda installation" do
    test "propagates install failure and restores LightpandaEx environment", %{directory: directory} do
      target = Path.join(directory, lightpanda_binary_name())

      with_lightpanda_ex(target, {:error, "fake lightpanda install failure"}, fn ->
        with_app_env(:lightpanda_ex, :version, "before-version", fn ->
          with_app_env(:lightpanda_ex, :path, "before-path", fn ->
            assert {:error, "fake lightpanda install failure"} =
                     Installer.install(:lightpanda, path: directory, force: true)

            assert Application.get_env(:lightpanda_ex, :version) == "before-version"
            assert Application.get_env(:lightpanda_ex, :path) == "before-path"
          end)
        end)
      end)
    end

    test "rejects a successful install that does not create a usable command", %{directory: directory} do
      target = Path.join(directory, lightpanda_binary_name())

      with_lightpanda_ex(target, :ok, fn ->
        assert {:error, reason} = Installer.install(:lightpanda, path: directory, force: true)
        assert reason =~ "installed lightpanda binary is not usable"
      end)
    end

    test "keeps successful installation behavior", %{directory: directory} do
      target = Path.join(directory, lightpanda_binary_name())

      with_lightpanda_ex(target, :create_usable_command, fn ->
        assert :ok = Installer.install(:lightpanda, path: directory, force: true)
        assert Installer.installed?(:lightpanda)
      end)
    end

    test "rejects success when a configured broken command remains selected", %{directory: directory} do
      target = Path.join(directory, lightpanda_binary_name())
      configured = write_command(Path.join(directory, "configured-lightpanda"), "exit 47")

      with_lightpanda_ex(target, :create_usable_command, fn ->
        with_app_env(:jido_browser, :lightpanda, [binary_path: configured], fn ->
          assert {:error, reason} = Installer.install(:lightpanda, path: directory, force: true)
          assert reason =~ "lightpanda installation completed"
          assert reason =~ "selected executable is not usable at #{configured}"
          refute Installer.installed?(:lightpanda)
          assert command_succeeds?(target, ["version"])
        end)
      end)
    end
  end

  defp expect_http_download(body) do
    expect(:httpc, :request, fn :get, {_url, []}, _http_options, body_format: :binary ->
      {:ok, {{~c"HTTP/1.1", 200, ~c"OK"}, [], body}}
    end)
  end

  defp with_fake_vibium_install(directory, opts, fun) do
    command_directory = Path.join(directory, "commands")
    npm_root = Path.join(directory, "npm-root")
    install_path = Path.join(directory, "install")
    package_bin = Path.join([npm_root, vibium_npm_package(), "bin"])
    source = Path.join(package_bin, vibium_binary_name())
    target = Path.join(install_path, vibium_binary_name())

    File.mkdir_p!(command_directory)
    File.mkdir_p!(package_bin)

    case Keyword.get(opts, :source_type, :command) do
      :command ->
        browser_status = Keyword.get(opts, :browser_install_status, 0)

        write_command(
          source,
          """
          case "$1" in
            version) printf 'vibium test\\n'; exit 0 ;;
            install) printf 'fake browser failure\\n'; exit #{browser_status} ;;
          esac
          exit 2
          """
        )

      :directory ->
        File.mkdir_p!(source)

      :missing ->
        :ok
    end

    npm_status = Keyword.get(opts, :npm_install_status, 0)

    write_command(
      Path.join(command_directory, "npm"),
      """
      if [ "$1" = "install" ]; then
        printf 'fake npm install\\n'
        exit #{npm_status}
      fi
      if [ "$1" = "root" ]; then
        printf '%s\\n' '#{npm_root}'
        exit 0
      fi
      exit 2
      """
    )

    with_app_env(:jido_browser, :path, install_path, fn ->
      with_system_path(command_directory, fn ->
        fun.(%{source: source, target: target})
      end)
    end)
  end

  defp with_lightpanda_ex(target, install_result, fun) do
    install_body =
      case install_result do
        :create_usable_command ->
          """
          File.write!(
            #{inspect(target)},
            "#!/bin/sh\\nif [ \\"$#\\" -eq 1 ] && [ \\"$1\\" = \\"version\\" ]; then exit 0; fi\\nexit 97\\n"
          )
          File.chmod!(#{inspect(target)}, 0o755)
          :ok
          """

        result ->
          inspect(result)
      end

    Code.compile_string("""
    defmodule LightpandaEx do
      def latest_version, do: "0.3.0"
      def bin_path, do: #{inspect(target)}
      def install do
        #{install_body}
      end
    end
    """)

    try do
      fun.()
    after
      :code.purge(LightpandaEx)
      :code.delete(LightpandaEx)
    end
  end

  defp write_command(path, body) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, "#!/bin/sh\n#{body}\n")
    File.chmod!(path, 0o755)
    path
  end

  defp command_succeeds?(path, args) do
    match?({_output, 0}, System.cmd(path, args, stderr_to_stdout: true))
  end

  defp exact_argument_command(argument, marker) do
    """
    if [ "$#" -eq 1 ] && [ "$1" = "#{argument}" ]; then
      printf '%s' "$1" > '#{marker}'
      exit 0
    fi
    exit 97
    """
  end

  defp with_app_env(app, key, value, fun) do
    previous = Application.get_env(app, key, :__missing__)
    Application.put_env(app, key, value)

    try do
      fun.()
    after
      restore_app_env(app, key, previous)
    end
  end

  defp restore_app_env(app, key, :__missing__), do: Application.delete_env(app, key)
  defp restore_app_env(app, key, value), do: Application.put_env(app, key, value)

  defp with_system_path(directory, fun) do
    previous = System.get_env("PATH")
    System.put_env("PATH", directory)

    try do
      fun.()
    after
      if previous, do: System.put_env("PATH", previous), else: System.delete_env("PATH")
    end
  end

  defp agent_browser_binary_name do
    case Installer.target() do
      :darwin_arm64 -> "agent-browser-darwin-arm64"
      :darwin_amd64 -> "agent-browser-darwin-x64"
      :linux_amd64 -> "agent-browser-linux-x64"
      :linux_arm64 -> "agent-browser-linux-arm64"
      :windows_amd64 -> "agent-browser-win32-x64.exe"
    end
  end

  defp web_binary_name do
    if Installer.target() == :windows_amd64, do: "web.exe", else: "web"
  end

  defp lightpanda_binary_name do
    if Installer.target() == :windows_amd64, do: "lightpanda.exe", else: "lightpanda"
  end

  defp vibium_npm_package do
    case Installer.target() do
      :darwin_arm64 -> "@vibium/darwin-arm64"
      :darwin_amd64 -> "@vibium/darwin-x64"
      :linux_amd64 -> "@vibium/linux-x64"
      :linux_arm64 -> "@vibium/linux-arm64"
      :windows_amd64 -> "@vibium/win32-x64"
    end
  end

  defp vibium_binary_name do
    if Installer.target() == :windows_amd64, do: "vibium.exe", else: "vibium"
  end
end
