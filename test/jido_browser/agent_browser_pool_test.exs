defmodule Jido.Browser.AgentBrowserPoolTest do
  use ExUnit.Case, async: false
  use Mimic

  alias Jido.Browser
  alias Jido.Browser.Adapters.AgentBrowser
  alias Jido.Browser.Pool
  alias Jido.Browser.TestPoolRuntime

  setup :set_mimic_global

  setup do
    stub(Jido.Browser.AgentBrowser.Runtime, :find_binary, fn -> {:ok, "/fake/agent-browser"} end)
    stub(Jido.Browser.AgentBrowser.Runtime, :ensure_supported_version, fn _binary -> :ok end)
    :ok
  end

  describe "warm pools" do
    test "start_pool waits for warm workers and duplicate names return already_started" do
      name = unique_pool_name()
      started_at = System.monotonic_time(:millisecond)

      assert {:ok, pid} =
               Browser.start_pool(
                 adapter: AgentBrowser,
                 name: name,
                 size: 2,
                 worker_init_delay: 50,
                 pool_runtime_module: TestPoolRuntime
               )

      on_exit(fn -> Browser.stop_pool(pid) end)

      elapsed = System.monotonic_time(:millisecond) - started_at
      assert elapsed >= 40

      assert {:error, {:already_started, ^pid}} =
               Browser.start_pool(
                 adapter: AgentBrowser,
                 name: name,
                 size: 2,
                 pool_runtime_module: TestPoolRuntime
               )
    end

    test "start_session waits for a warm pooled session and times out when exhausted" do
      name = unique_pool_name()
      assert {:ok, pool} = start_pool!(name, size: 1)
      on_exit(fn -> Browser.stop_pool(pool) end)

      assert {:ok, session} = Browser.start_session(pool: name)

      task =
        Task.async(fn ->
          Browser.start_session(pool: name, checkout_timeout: 50)
        end)

      assert {:error, reason} = Task.await(task, 2_000)
      assert Exception.message(reason) =~ "Timed out waiting for a warm pooled session"

      assert :ok = Browser.end_session(session)
    end

    test "end_session recycles the worker and returns a replacement" do
      name = unique_pool_name()
      assert {:ok, pool} = start_pool!(name, size: 1)
      on_exit(fn -> Browser.stop_pool(pool) end)

      assert {:ok, session_one} = Browser.start_session(pool: name)
      session_id_one = session_one.connection.session_id
      assert :ok = Browser.end_session(session_one)

      assert {:ok, session_two} = Browser.start_session(pool: name)
      refute session_two.connection.session_id == session_id_one
      assert :ok = Browser.end_session(session_two)
    end

    test "pooled command errors keep the lease usable until explicit end" do
      name = unique_pool_name()
      assert {:ok, pool} = start_pool!(name, size: 1)
      on_exit(fn -> Browser.stop_pool(pool) end)

      assert {:ok, session} = Browser.start_session(pool: name)

      assert {:error, _reason} = Browser.navigate(session, "fail://page")

      assert {:ok, _updated_session, %{"url" => "https://example.com"}} =
               Browser.navigate(session, "https://example.com")

      assert :ok = Browser.end_session(session)
    end

    test "transport failures return clean errors and release still recycles" do
      name = unique_pool_name()
      assert {:ok, pool} = start_pool!(name, size: 1)
      on_exit(fn -> Browser.stop_pool(pool) end)

      assert {:ok, session} = Browser.start_session(pool: name)

      assert {:error, _reason} = Browser.navigate(session, "crash://daemon")
      assert {:error, _reason} = Browser.navigate(session, "https://example.com")
      assert :ok = Browser.end_session(session)

      assert {:ok, replacement} = Browser.start_session(pool: name)
      assert :ok = Browser.end_session(replacement)
    end

    test "stale pooled leases return adapter errors instead of exiting callers" do
      name = unique_pool_name()
      assert {:ok, pool} = start_pool!(name, size: 1)
      on_exit(fn -> Browser.stop_pool(pool) end)

      assert {:ok, session} = Browser.start_session(pool: name)
      lease_pid = session.runtime.manager
      ref = Process.monitor(lease_pid)

      Process.exit(lease_pid, :kill)
      assert_receive {:DOWN, ^ref, :process, ^lease_pid, _reason}, 1_000

      assert {:error, error} = Browser.navigate(session, "https://example.com")
      assert %Jido.Browser.Error.AdapterError{details: %{reason: :lease_unavailable}} = error

      assert :ok = Browser.end_session(session)

      assert {:ok, replacement} = Browser.start_session(pool: name, checkout_timeout: 500)
      assert :ok = Browser.end_session(replacement)
    end

    test "caller crashes discard the lease and a replacement can be checked out" do
      name = unique_pool_name()
      assert {:ok, pool} = start_pool!(name, size: 1)
      on_exit(fn -> Browser.stop_pool(pool) end)

      parent = self()

      worker =
        spawn(fn ->
          {:ok, session} = Browser.start_session(pool: name)
          send(parent, {:leased_session, session.connection.session_id})
          Process.sleep(:infinity)
        end)

      session_id =
        receive do
          {:leased_session, id} -> id
        after
          1_000 -> flunk("timed out waiting for leased session")
        end

      ref = Process.monitor(worker)
      Process.exit(worker, :kill)
      assert_receive {:DOWN, ^ref, :process, ^worker, _reason}, 1_000

      Process.sleep(100)

      assert {:ok, replacement} = Browser.start_session(pool: name, checkout_timeout: 500)
      refute replacement.connection.session_id == session_id
      assert :ok = Browser.end_session(replacement)
    end

    test "pooled sessions stay bound to the checkout owner" do
      name = unique_pool_name()
      assert {:ok, pool} = start_pool!(name, size: 1)
      on_exit(fn -> Browser.stop_pool(pool) end)

      assert {:ok, session} = Browser.start_session(pool: name)
      owner = self()

      task =
        Task.async(fn ->
          send(owner, {:cross_process_attempt, self()})

          {
            Browser.navigate(session, "https://example.com"),
            Browser.end_session(session)
          }
        end)

      caller_pid =
        receive do
          {:cross_process_attempt, pid} -> pid
        after
          1_000 -> flunk("timed out waiting for cross-process call")
        end

      assert {{:error, navigate_error}, {:error, shutdown_error}} = Task.await(task, 2_000)
      assert %Jido.Browser.Error.AdapterError{details: %{reason: {:not_owner, ^owner}}} = navigate_error
      assert %Jido.Browser.Error.AdapterError{details: %{reason: {:not_owner, ^owner}}} = shutdown_error
      refute caller_pid == owner

      assert :ok = Browser.end_session(session)
    end
  end

  describe "pool validation" do
    test "unsupported adapters return clear errors" do
      assert {:error, error} =
               Browser.start_pool(adapter: Jido.Browser.Adapters.Web, name: unique_pool_name(), size: 1)

      assert Exception.message(error) =~ "does not support pooled sessions"

      assert {:error, error} =
               Browser.start_session(adapter: Jido.Browser.Adapters.Web, pool: unique_pool_name())

      assert Exception.message(error) =~ "does not support pooled sessions"
    end

    test "session_name is rejected for pooled start and pool startup" do
      name = unique_pool_name()

      assert {:error, error} =
               Browser.start_pool(
                 adapter: AgentBrowser,
                 name: name,
                 size: 1,
                 session_name: "persisted",
                 pool_runtime_module: TestPoolRuntime
               )

      assert Exception.message(error) =~ "do not support session_name"

      assert {:ok, pool} = start_pool!(name, size: 1)
      on_exit(fn -> Browser.stop_pool(pool) end)

      assert {:error, error} =
               Browser.start_session(pool: name, session_name: "persisted")

      assert Exception.message(error) =~ "do not support session_name"
    end

    test "supervised pool child starts under a consumer supervisor and is usable by name" do
      pool_name = {:global, {:browser_pool, System.unique_integer([:positive])}}
      started_at = System.monotonic_time(:millisecond)

      start_supervised!({Pool, name: pool_name, size: 1, worker_init_delay: 50, pool_runtime_module: TestPoolRuntime})

      elapsed = System.monotonic_time(:millisecond) - started_at
      assert elapsed >= 40

      assert {:ok, session} = Browser.start_session(pool: pool_name)
      assert :ok = Browser.end_session(session)
    end

    test "supervised pool child rejects invalid process names" do
      assert {:error, error} =
               Pool.start_link(name: "default", size: 1, pool_runtime_module: TestPoolRuntime)

      assert Exception.message(error) =~ "Supervised pool name must be an atom"
    end

    test "supervised pool child rejects unsupported adapters" do
      assert {:error, error} =
               Pool.start_link(name: :default, size: 1, adapter: Jido.Browser.Adapters.Web)

      assert Exception.message(error) =~ "does not support supervised warm pools"
    end
  end

  defp start_pool!(name, opts) do
    Browser.start_pool(
      Keyword.merge(
        [adapter: AgentBrowser, name: name, size: 1, pool_runtime_module: TestPoolRuntime],
        opts
      )
    )
  end

  defp unique_pool_name do
    "pool-#{System.unique_integer([:positive])}"
  end
end
