defmodule Jido.Browser.WarmPoolRuntimeTest do
  use ExUnit.Case, async: false

  alias Jido.Browser.WarmPool.Manager
  alias Jido.Browser.WarmPool.Runtime
  alias Jido.Browser.WarmPool.TreeSupervisor

  defmodule RuntimeProbe do
    alias Jido.Browser.WarmPool.Runtime

    @behaviour Runtime

    @impl true
    def start_worker(pool_state) do
      test_pid = Keyword.fetch!(pool_state.worker_opts, :test_pid)
      send(test_pid, {:runtime_context, Runtime.context(pool_state)})

      {:ok, %{session_id: "runtime-context-probe", test_pid: test_pid}}
    end

    @impl true
    def command(_worker_state, _payload, _timeout), do: {:error, :unsupported}

    @impl true
    def shutdown_worker(worker_state) do
      send(worker_state.test_pid, :runtime_probe_stopped)
      :ok
    end
  end

  test "runtime context passes adapter data through without interpretation" do
    callback = fn value -> {:ok, value} end
    context = %{start: callback, metadata: {:adapter, "agent-browser"}}
    name = "runtime-context-#{System.unique_integer([:positive])}"

    assert {:ok, pool} =
             TreeSupervisor.start_pool(
               name: name,
               size: 1,
               adapter: __MODULE__,
               worker_opts: [test_pid: self()],
               pool_runtime_module: RuntimeProbe,
               pool_runtime_context: context
             )

    on_exit(fn -> TreeSupervisor.stop_pool(pool) end)

    assert_receive {:runtime_context, received_context}
    assert received_context === context
    assert Runtime.context(%{worker_opts: []}) == nil
    assert callback.(123) == {:ok, 123}

    assert {:ok, manager} = Manager.resolve(name)
    manager_ref = Process.monitor(manager)
    Process.exit(manager, :kill)
    assert_receive {:DOWN, ^manager_ref, :process, ^manager, :killed}

    assert_receive {:runtime_context, restarted_context}
    assert restarted_context === context
    assert {:ok, restarted_manager} = Manager.resolve(name)
    refute restarted_manager == manager
  end
end
