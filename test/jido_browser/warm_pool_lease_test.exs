defmodule Jido.Browser.WarmPoolLeaseTest do
  use ExUnit.Case, async: false

  alias Jido.Browser.TestPoolRuntime
  alias Jido.Browser.WarmPool.Lease
  alias Jido.Browser.WarmPool.Worker

  test "command returns lease_not_ready before checkout completes" do
    cleanup_supervisor = start_supervised!({Task.Supervisor, name: nil})

    {:ok, pool} =
      NimblePool.start_link(
        worker:
          {Worker,
           %{
             manager: self(),
             worker_opts: [worker_init_delay: 200],
             cleanup_supervisor: cleanup_supervisor,
             runtime_module: TestPoolRuntime
           }},
        pool_size: 1
      )

    {:ok, lease} =
      Lease.start_link(
        owner: self(),
        pool: pool,
        runtime_module: TestPoolRuntime,
        checkout_timeout: 1_000
      )

    assert {:error, :lease_not_ready} = Lease.command(lease, %{"action" => "title"}, 50)
    assert {:ok, _worker_state} = Lease.await_ready(lease, 2_000)
    assert :ok = Lease.shutdown(lease)
  end
end
