defmodule Jido.Browser.AgentBrowserRuntimeTest do
  use ExUnit.Case, async: false

  alias Jido.Browser.AgentBrowser.PoolRuntime
  alias Jido.Browser.AgentBrowser.Runtime
  alias Jido.Browser.AgentBrowser.SessionServer
  alias Jido.Browser.Application, as: BrowserApplication
  alias Jido.Browser.TestSupport.FakeAgentBrowser

  describe "application bootstrap" do
    test "ensure_started restarts the browser application after it has been stopped" do
      assert :ok = BrowserApplication.ensure_started()
      assert :ok = Application.stop(:jido_browser)
      assert :ok = BrowserApplication.ensure_started(2_000)

      assert Process.alive?(Process.whereis(Jido.Browser.WarmPool.RootSupervisor))
      assert Process.alive?(Process.whereis(Jido.Browser.WarmPool.Registry))
      assert Process.alive?(Process.whereis(Jido.Browser.WarmPool.Supervisor))
    end
  end

  describe "session server" do
    test "starts, serves commands, and shuts down cleanly" do
      with_trapped_exits(fn ->
        FakeAgentBrowser.with_binary(:normal, fn binary, _socket_dir ->
          session_id = unique_session_id("session-server")
          assert {:ok, pid} = SessionServer.start_link(session_id: session_id, binary: binary, registration: :none)

          assert %{
                   endpoint: %{path: path, type: :unix},
                   manager: ^pid,
                   session_id: ^session_id,
                   transport: :agent_browser_ipc
                 } = SessionServer.metadata(pid)

          assert String.ends_with?(path, "#{session_id}.sock")

          assert {:ok, %{"url" => "https://example.com"}} =
                   SessionServer.command(pid, %{"action" => "navigate", "url" => "https://example.com"}, 1_000)

          assert {:ok, %{"title" => "Title for https://example.com", "url" => "https://example.com"}} =
                   SessionServer.command(pid, %{"action" => "title"}, 1_000)

          ref = Process.monitor(pid)
          assert :ok = SessionServer.shutdown(pid)
          assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1_000
        end)
      end)
    end

    test "returns a startup error when the daemon exits during boot" do
      with_trapped_exits(fn ->
        FakeAgentBrowser.with_binary(:exit_on_start, fn binary, _socket_dir ->
          session_id = unique_session_id("startup-fail")

          assert {:error, reason} =
                   SessionServer.start_link(session_id: session_id, binary: binary, registration: :none)

          assert reason =~ "agent-browser daemon exited with 13"
          assert reason =~ "boot failure"
        end)
      end)
    end

    test "retries transient command failures before surfacing an error" do
      with_trapped_exits(fn ->
        FakeAgentBrowser.with_binary(:flaky_navigate, fn binary, _socket_dir ->
          session_id = unique_session_id("retry")
          assert {:ok, pid} = SessionServer.start_link(session_id: session_id, binary: binary, registration: :none)

          on_exit(fn ->
            if Process.alive?(pid) do
              Process.unlink(pid)

              try do
                SessionServer.shutdown(pid)
              catch
                :exit, _reason -> :ok
              end
            else
              :ok
            end
          end)

          assert {:ok, %{"url" => "https://example.com"}} =
                   SessionServer.command(pid, %{"action" => "navigate", "url" => "https://example.com"}, 1_000)
        end)
      end)
    end

    test "stops when the daemon exits after startup" do
      with_trapped_exits(fn ->
        FakeAgentBrowser.with_binary(:exit_on_navigate, fn binary, _socket_dir ->
          session_id = unique_session_id("daemon-exit")
          assert {:ok, pid} = SessionServer.start_link(session_id: session_id, binary: binary, registration: :none)
          ref = Process.monitor(pid)

          assert {:ok, %{"url" => "https://example.com"}} =
                   SessionServer.command(pid, %{"action" => "navigate", "url" => "https://example.com"}, 1_000)

          assert_receive {:DOWN, ^ref, :process, ^pid, {:daemon_exit, 56, _stderr}}, 1_000
        end)
      end)
    end
  end

  describe "pool runtime" do
    test "starts a pool-local worker, dispatches commands, and shuts it down" do
      FakeAgentBrowser.with_binary(:normal, fn binary, _socket_dir ->
        session_supervisor = start_supervised!({DynamicSupervisor, strategy: :one_for_one})

        assert {:ok, worker_state} =
                 PoolRuntime.start_worker(%{
                   worker_opts: [binary: binary, timeout: 1_000],
                   session_supervisor: session_supervisor
                 })

        assert :ok = PoolRuntime.health_check(worker_state)

        assert {:ok, %{"url" => "https://example.com"}} =
                 PoolRuntime.command(worker_state, %{"action" => "navigate", "url" => "https://example.com"}, 1_000)

        manager = worker_state.manager
        ref = Process.monitor(manager)
        assert :ok = PoolRuntime.shutdown_worker(worker_state)
        assert_receive {:DOWN, ^ref, :process, ^manager, :normal}, 1_000
        assert {:error, :session_unavailable} = PoolRuntime.health_check(worker_state)
      end)
    end
  end

  describe "runtime helpers" do
    test "find_binary respects configured paths" do
      with_temporary_script("#!/bin/sh\nexit 0\n", fn binary ->
        with_agent_browser_config([binary_path: binary], fn ->
          assert {:ok, ^binary} = Runtime.find_binary()
        end)
      end)

      with_agent_browser_config([binary_path: "/missing/agent-browser"], fn ->
        assert {:error, "Binary not found at /missing/agent-browser"} = Runtime.find_binary()
      end)
    end

    test "parse_version and ensure_supported_version validate the binary version" do
      assert {:ok, "0.20.2"} = Runtime.parse_version("agent-browser 0.20.2\n")
      assert {:error, "unknown output"} = Runtime.parse_version("unknown output")

      with_temporary_script("#!/bin/sh\nprintf 'agent-browser 0.20.2\\n'\n", fn binary ->
        assert :ok = Runtime.ensure_supported_version(binary)
      end)

      with_temporary_script("#!/bin/sh\nprintf 'agent-browser 0.19.0\\n'\n", fn binary ->
        assert {:error, error} = Runtime.ensure_supported_version(binary)
        assert Exception.message(error) =~ "Unsupported agent-browser version"
      end)

      with_temporary_script("#!/bin/sh\nprintf 'broken\\n'\nexit 2\n", fn binary ->
        assert {:error, error} = Runtime.ensure_supported_version(binary)
        assert Exception.message(error) =~ "Failed to inspect agent-browser version"
      end)
    end

    test "ensure_session_server registers a live session server" do
      FakeAgentBrowser.with_binary(:normal, fn binary, _socket_dir ->
        session_id = unique_session_id("runtime")

        assert {:ok, pid, runtime} =
                 Runtime.ensure_session_server(session_id, binary: binary, timeout: 1_000)

        assert runtime.transport == :agent_browser_ipc
        assert runtime.session_id == session_id
        assert {:ok, ^pid} = Runtime.lookup_session_server(session_id)
        assert :ok = SessionServer.shutdown(pid)
      end)
    end

    test "daemon_env includes boolean, timeout, and list options" do
      env =
        Runtime.daemon_env("session-123",
          headed: true,
          debug: true,
          session_name: "persisted",
          timeout: 4_000,
          allowed_domains: ["example.com", "example.org"]
        )

      assert {"AGENT_BROWSER_SESSION", "session-123"} in env
      assert {"AGENT_BROWSER_HEADED", "1"} in env
      assert {"AGENT_BROWSER_DEBUG", "1"} in env
      assert {"AGENT_BROWSER_SESSION_NAME", "persisted"} in env
      assert {"AGENT_BROWSER_DEFAULT_TIMEOUT", "4000"} in env
      assert {"AGENT_BROWSER_ALLOWED_DOMAINS", "example.com,example.org"} in env
    end
  end

  defp with_agent_browser_config(config, fun) do
    old_config = Application.get_env(:jido_browser, :agent_browser, [])
    Application.put_env(:jido_browser, :agent_browser, Keyword.merge(old_config, config))

    try do
      fun.()
    after
      Application.put_env(:jido_browser, :agent_browser, old_config)
    end
  end

  defp with_temporary_script(body, fun) do
    tmp_dir =
      Path.join(System.tmp_dir!(), "jido_browser_runtime_#{System.unique_integer([:positive])}")

    path = Path.join(tmp_dir, "agent-browser")
    File.mkdir_p!(tmp_dir)
    File.write!(path, body)
    File.chmod!(path, 0o755)

    try do
      fun.(path)
    after
      File.rm_rf(tmp_dir)
    end
  end

  defp unique_session_id(prefix) do
    "#{prefix}-#{System.unique_integer([:positive])}"
  end

  defp with_trapped_exits(fun) do
    old = Process.flag(:trap_exit, true)

    try do
      fun.()
    after
      Process.flag(:trap_exit, old)
    end
  end
end
