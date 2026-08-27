defmodule Jido.Browser.AgentBrowserRuntimeTest do
  use ExUnit.Case, async: false

  alias Jido.Browser.Adapters.AgentBrowser
  alias Jido.Browser.AgentBrowser.PoolRuntime
  alias Jido.Browser.AgentBrowser.Runtime
  alias Jido.Browser.AgentBrowser.SessionServer
  alias Jido.Browser.Application, as: BrowserApplication
  alias Jido.Browser.TestSupport.FakeAgentBrowser
  alias Jido.Browser.WarmPool.Names

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

  describe "adapter daemon payloads" do
    test "resolves zero-based indexes against ordered stable tab identifiers" do
      FakeAgentBrowser.with_binary(:normal, fn binary, _socket_dir ->
        with_agent_browser_config([binary_path: binary], fn ->
          assert {:ok, session} = Jido.Browser.start_session(adapter: AgentBrowser, timeout: 1_000)

          try do
            assert {:ok, ^session, %{"tabId" => "t2"}} =
                     Jido.Browser.switch_tab(session, 1, timeout: 1_000)

            assert {:ok, ^session, %{"tabId" => "t1"}} =
                     Jido.Browser.close_tab(session, 0, timeout: 1_000)

            assert {:ok, ^session, %{"tabId" => "t2"}} =
                     Jido.Browser.switch_tab(session, 0, timeout: 1_000)

            assert {:ok, ^session, %{"tabId" => "t3"}} =
                     Jido.Browser.close_tab(session, 1, timeout: 1_000)
          after
            Jido.Browser.end_session(session)
          end
        end)
      end)
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
    test "the AgentBrowser adapter wires the default pool runtime and keeps pool registration" do
      FakeAgentBrowser.with_binary(:normal, fn binary, _socket_dir ->
        with_agent_browser_config([binary_path: binary], fn ->
          name = "agent-browser-runtime-#{System.unique_integer([:positive])}"

          assert {:ok, pool} =
                   Jido.Browser.start_pool(
                     adapter: AgentBrowser,
                     name: name,
                     size: 1,
                     timeout: 1_000,
                     startup_timeout: 5_000
                   )

          try do
            assert {:ok, ^pool} = Names.resolve_tree(name)
            assert {:ok, manager} = Names.resolve_manager(name)
            assert Process.alive?(manager)

            assert {:ok, session} = Jido.Browser.start_session(adapter: AgentBrowser, pool: name)
            assert session.adapter == AgentBrowser
            assert session.runtime.pool == name
            assert session.runtime.pooled == true
            assert session.runtime.manager_module == Jido.Browser.WarmPool.Lease
            assert session.opts.checkout_timeout == 5_000
            assert :error = Runtime.lookup_session_server(session.runtime.session_id)

            assert {:ok, ^session, %{"title" => "Ready", "url" => nil}} =
                     Jido.Browser.get_title(session, timeout: 1_000)

            assert :ok = Jido.Browser.end_session(session)
          after
            assert :ok = Jido.Browser.stop_pool(pool)
          end

          assert_eventually(fn ->
            assert {:error, :pool_not_found} = Names.resolve_tree(name)
            assert {:error, :pool_not_found} = Names.resolve_manager(name)
          end)
        end)
      end)
    end

    test "starts a pool-local worker, dispatches commands, and shuts it down" do
      FakeAgentBrowser.with_binary(:normal, fn binary, _socket_dir ->
        session_supervisor = start_supervised!({DynamicSupervisor, strategy: :one_for_one})

        assert {:ok, worker_state} =
                 PoolRuntime.start_worker(%{
                   worker_opts: [binary: binary, timeout: 1_000],
                   session_supervisor: session_supervisor,
                   runtime_context: %{session_runtime_metadata: &Runtime.session_runtime_metadata/2}
                 })

        assert worker_state.binary == binary
        assert worker_state.health_check_timeout == 2_000
        assert worker_state.runtime.transport == :agent_browser_ipc
        assert worker_state.runtime.session_id == worker_state.session_id
        assert worker_state.runtime.manager == worker_state.manager
        assert :error = Runtime.lookup_session_server(worker_state.session_id)

        assert Enum.any?(DynamicSupervisor.which_children(session_supervisor), fn
                 {_id, pid, :worker, [SessionServer]} -> pid == worker_state.manager
                 _child -> false
               end)

        assert :ok = PoolRuntime.health_check(worker_state)

        assert {:ok, %{"url" => "https://example.com"}} =
                 PoolRuntime.command(worker_state, %{"action" => "navigate", "url" => "https://example.com"}, 1_000)

        manager = worker_state.manager
        ref = Process.monitor(manager)
        assert :ok = PoolRuntime.shutdown_worker(worker_state)
        assert_receive {:DOWN, ^ref, :process, ^manager, :normal}, 1_000
        assert {:error, :session_unavailable} = PoolRuntime.health_check(worker_state)
        assert DynamicSupervisor.which_children(session_supervisor) == []
      end)
    end
  end

  describe "runtime helpers" do
    test "find_binary respects configured paths" do
      with_temporary_script("#!/bin/sh\nprintf 'agent-browser 0.35.1\\n'\n", fn binary ->
        with_agent_browser_config([binary_path: binary], fn ->
          assert {:ok, ^binary} = Runtime.find_binary()
        end)
      end)

      with_agent_browser_config([binary_path: "/missing/agent-browser"], fn ->
        assert {:error, error} = Runtime.find_binary()
        assert Exception.message(error) == "Configured agent-browser binary was not found"
      end)
    end

    test "parse_version and ensure_supported_version validate the binary version" do
      assert {:ok, "0.35.1"} = Runtime.parse_version("agent-browser 0.35.1\n")
      assert {:error, "unknown output"} = Runtime.parse_version("unknown output")

      with_temporary_script("#!/bin/sh\nprintf 'agent-browser 0.35.1\\n'\n", fn binary ->
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

  defp assert_eventually(fun, attempts \\ 100)

  defp assert_eventually(fun, attempts) when attempts > 0 do
    fun.()
  rescue
    error ->
      if attempts == 1 do
        reraise error, __STACKTRACE__
      else
        Process.sleep(10)
        assert_eventually(fun, attempts - 1)
      end
  end
end
