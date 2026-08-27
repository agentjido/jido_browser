defmodule Jido.Browser.BrowseyExecTest do
  use ExUnit.Case, async: false

  alias Jido.Browser.Vendor.BrowseyHttp.Util.Exec

  @fast_exit_iterations 500
  @fixture_term_wait_ms 250
  @fixture_kill_wait_ms 1_000

  test "repeated fast successful exits return their existing result and preserve an unrelated process" do
    with_trap_exit(fn ->
      executable = System.find_executable("true") || "/usr/bin/true"

      with_unrelated_process(fn unrelated_port, unrelated_pid ->
        for _iteration <- 1..@fast_exit_iterations do
          assert {:ok, [stdout: [], stderr: [""]]} = Exec.exec(executable, [], 1_000)
        end

        assert os_process_alive?(unrelated_pid)
        assert linked_ports() == [unrelated_port]
        refute_port_messages()
      end)
    end)
  end

  test "repeated fast non-zero exits return their existing result" do
    with_trap_exit(fn ->
      executable = System.find_executable("false") || "/usr/bin/false"

      for _iteration <- 1..@fast_exit_iterations do
        assert {:error, result} = Exec.exec(executable, [], 1_000)
        assert result[:exit_status] == 1
        assert result[:observed_bytes] == 0
        assert result[:stdout] == []
        assert result[:stderr] == [""]
      end

      assert linked_ports() == []
      refute_port_messages()
    end)
  end

  test "deterministically collects a successful process that exits before PID discovery" do
    with_trap_exit(fn ->
      with_unrelated_process(fn unrelated_port, unrelated_pid ->
        unrelated_exit_pid = queue_unrelated_exit()
        unrelated_exit_port = queue_unrelated_port_exit()
        script = controlled_script(~s(printf forced-success; printf forced-diagnostic > "$3"))

        {result, port, os_pid, stderr_path} = controlled_exec(script, nil)

        assert {:ok, output} = result
        assert IO.iodata_to_binary(output[:stdout]) == "forced-success"
        assert IO.iodata_to_binary(output[:stderr]) == "forced-diagnostic"
        refute File.exists?(stderr_path)
        assert_exact_port_reaped(port, os_pid)

        assert os_process_alive?(unrelated_pid)
        assert linked_ports() == [unrelated_port]
        assert_receive {:EXIT, ^unrelated_exit_pid, :unrelated_exit}, 0
        assert_receive {:EXIT, ^unrelated_exit_port, :normal}, 0
        refute_port_messages()
      end)
    end)
  end

  test "deterministically collects a non-zero process that exits before PID discovery" do
    with_trap_exit(fn ->
      script = controlled_script(~s(printf forced-failure; printf forced-error > "$3"; exit 17))

      {result, port, os_pid, stderr_path} = controlled_exec(script, nil)

      assert {:error, output} = result
      assert output[:exit_status] == 17
      assert output[:observed_bytes] == byte_size("forced-failure")
      assert IO.iodata_to_binary(output[:stdout]) == "forced-failure"
      assert IO.iodata_to_binary(output[:stderr]) == "forced-error"
      refute File.exists?(stderr_path)
      assert_exact_port_reaped(port, os_pid)
      refute_port_messages()
    end)
  end

  test "deterministically applies the response limit after a process exits before PID discovery" do
    with_trap_exit(fn ->
      with_unrelated_process(fn unrelated_port, unrelated_pid ->
        script = controlled_script(~s(printf 123456; printf limit-error > "$3"))

        {result, port, os_pid, stderr_path} = controlled_exec(script, nil, 4)

        assert {:error, output} = result
        assert output[:exit_status] == 63
        assert output[:observed_bytes] == 6
        assert output[:response_too_large?] == true
        assert output[:stdout] == []
        assert IO.iodata_to_binary(output[:stderr]) == "limit-error"
        refute File.exists?(stderr_path)
        assert_exact_port_reaped(port, os_pid)

        assert os_process_alive?(unrelated_pid)
        assert linked_ports() == [unrelated_port]
        refute_port_messages()
      end)
    end)
  end

  test "normal fixture cleanup neutralizes its late fallback" do
    with_trap_exit(fn ->
      fixture = start_unrelated_process()
      {port, _monitor_ref, os_pid, completion} = fixture

      try do
        assert os_process_alive?(os_pid)
        assert linked_ports() == [port]
      after
        complete_unrelated_process_cleanup(fixture)
      end

      signal_ref = make_ref()
      owner = self()

      assert :already_complete =
               fallback_cleanup_unrelated_process(port, os_pid, completion, fn pid, signal ->
                 send(owner, {signal_ref, pid, signal})
               end)

      refute_receive {^signal_ref, ^os_pid, _signal}, 0
      refute_port_messages()
    end)
  end

  test "fallback does not signal an unrelated PID after the recorded port closes" do
    with_trap_exit(fn ->
      with_unrelated_process(fn _unrelated_port, unrelated_pid ->
        closed_port = closed_test_port()
        active_completion = new_fixture_completion()
        signal_ref = make_ref()
        owner = self()

        assert {:not_owned, nil} =
                 fallback_cleanup_unrelated_process(closed_port, unrelated_pid, active_completion, fn pid, signal ->
                   send(owner, {signal_ref, pid, signal})
                 end)

        refute_receive {^signal_ref, ^unrelated_pid, _signal}, 0
        assert os_process_alive?(unrelated_pid)
        refute_port_messages()
      end)
    end)
  end

  test "reaps exact port EXIT signals after successful and non-zero exits" do
    with_trap_exit(fn ->
      success_script = controlled_script(~s(printf normal; printf diagnostic > "$3"))
      {success, success_port, success_pid, success_stderr} = controlled_exec(success_script, :exact)

      assert {:ok, success_output} = success
      assert IO.iodata_to_binary(success_output[:stdout]) == "normal"
      assert IO.iodata_to_binary(success_output[:stderr]) == "diagnostic"
      refute File.exists?(success_stderr)
      assert_exact_port_reaped(success_port, success_pid)

      failure_script = controlled_script(~s(printf failed; printf failure > "$3"; exit 9))
      {failure, failure_port, failure_pid, failure_stderr} = controlled_exec(failure_script, :exact)

      assert {:error, failure_output} = failure
      assert failure_output[:exit_status] == 9
      assert IO.iodata_to_binary(failure_output[:stdout]) == "failed"
      assert IO.iodata_to_binary(failure_output[:stderr]) == "failure"
      refute File.exists?(failure_stderr)
      assert_exact_port_reaped(failure_port, failure_pid)
      refute_port_messages()
    end)
  end

  test "terminates and reaps the exact port process and EXIT signal on timeout" do
    with_trap_exit(fn ->
      script = controlled_script(~s(trap '' TERM; printf timeout > "$3"; while :; do :; done))

      {result, port, os_pid, stderr_path} = controlled_exec(script, :exact, :infinity, 100)

      assert {:error, output} = result
      assert output[:exit_status] == 28
      assert IO.iodata_to_binary(output[:stderr]) == "timeout"
      refute File.exists?(stderr_path)
      assert_exact_port_reaped(port, os_pid)
    end)
  end

  test "terminates and reaps the exact port process and EXIT signal at the response limit" do
    with_trap_exit(fn ->
      script =
        controlled_script(~s(trap '' TERM; printf response-limit > "$3"; printf 123456; while :; do :; done))

      {result, port, os_pid, stderr_path} = controlled_exec(script, :exact, 4)

      assert {:error, output} = result
      assert output[:exit_status] == 63
      assert output[:observed_bytes] > 4
      assert output[:response_too_large?] == true
      assert output[:stdout] == []
      assert IO.iodata_to_binary(output[:stderr]) == "response-limit"
      refute File.exists?(stderr_path)
      assert_exact_port_reaped(port, os_pid)
    end)
  end

  defp controlled_script(body) do
    ~s(while [ ! -f "$1" ]; do :; done; printf '%s' "$3" > "$0"; #{body})
  end

  defp controlled_exec(script, pid_result, max_output_bytes \\ :infinity, timeout \\ 1_000) do
    shell = System.find_executable("sh") || "/bin/sh"
    details_path = tmp_path("browsey_controlled_details")
    gate_path = tmp_path("browsey_controlled_gate")
    File.rm(details_path)
    File.rm(gate_path)
    on_exit(fn -> File.rm(details_path) end)
    on_exit(fn -> File.rm(gate_path) end)

    owner = self()
    lookup_ref = make_ref()
    pid_lookup = controlled_pid_lookup(owner, lookup_ref, gate_path, details_path, pid_result)

    result = Exec.__test_exec__(shell, ["-c", script, details_path, gate_path], timeout, max_output_bytes, pid_lookup)
    assert_receive {^lookup_ref, port, os_pid}, 0
    stderr_path = File.read!(details_path)
    File.rm(details_path)
    File.rm(gate_path)

    {result, port, os_pid, stderr_path}
  end

  defp controlled_pid_lookup(owner, lookup_ref, gate_path, details_path, pid_result) do
    fn port ->
      {:os_pid, os_pid} = Port.info(port, :os_pid)
      send(owner, {lookup_ref, port, os_pid})
      File.write!(gate_path, "run")
      true = wait_until(fn -> existing_file?(details_path) end, 1_000)
      controlled_pid_result(pid_result, port, os_pid)
    end
  end

  defp controlled_pid_result(:exact, _port, os_pid), do: {:os_pid, os_pid}

  defp controlled_pid_result(nil, port, _os_pid) do
    true = wait_until(fn -> closed_port?(port) end, 1_000)
    nil
  end

  defp closed_port?(port) do
    if Port.info(port) == nil, do: true
  end

  defp existing_file?(path) do
    if File.exists?(path), do: true
  end

  defp with_trap_exit(fun) do
    previous = Process.flag(:trap_exit, true)

    try do
      result = fun.()
      assert Process.info(self(), :trap_exit) == {:trap_exit, true}
      result
    after
      Process.flag(:trap_exit, previous)
    end
  end

  defp queue_unrelated_exit do
    pid = spawn_link(fn -> exit(:unrelated_exit) end)

    assert wait_until(
             fn ->
               {:messages, messages} = Process.info(self(), :messages)
               if Enum.any?(messages, &match?({:EXIT, ^pid, :unrelated_exit}, &1)), do: true
             end,
             1_000
           )

    pid
  end

  defp queue_unrelated_port_exit do
    executable = System.find_executable("true") || "/usr/bin/true"
    port = Port.open({:spawn_executable, executable}, [:exit_status])
    assert_receive {^port, {:exit_status, 0}}, 1_000

    assert wait_until(
             fn ->
               {:messages, messages} = Process.info(self(), :messages)
               if Enum.any?(messages, &match?({:EXIT, ^port, :normal}, &1)), do: true
             end,
             1_000
           )

    port
  end

  defp wait_until(fun, timeout) do
    deadline = System.monotonic_time(:millisecond) + timeout
    wait_until(fun, deadline, nil)
  end

  defp wait_until(fun, deadline, fallback) do
    case fun.() do
      nil ->
        if System.monotonic_time(:millisecond) >= deadline do
          fallback
        else
          Process.sleep(5)
          wait_until(fun, deadline, fallback)
        end

      value ->
        value
    end
  end

  defp assert_exact_port_reaped(port, os_pid) do
    assert Port.info(port) == nil
    refute os_process_alive?(os_pid)
    refute port in linked_ports()

    {:messages, messages} = Process.info(self(), :messages)
    refute Enum.any?(messages, &exact_port_message?(&1, port))
  end

  defp exact_port_message?({port, {:data, _data}}, port), do: true
  defp exact_port_message?({port, {:exit_status, _status}}, port), do: true
  defp exact_port_message?({:EXIT, port, _reason}, port), do: true
  defp exact_port_message?({:DOWN, _ref, :port, port, _reason}, port), do: true
  defp exact_port_message?(_message, _port), do: false

  defp os_process_alive?(pid) do
    case os_process_alive_result(pid) do
      {:ok, alive?} -> alive?
      :timeout -> flunk("OS process check did not return")
    end
  end

  defp os_process_alive_result(pid) do
    owner = self()
    result_ref = make_ref()

    spawn(fn ->
      result = System.cmd(kill_path(), ["-0", Integer.to_string(pid)], stderr_to_stdout: true, env: %{})
      send(owner, {result_ref, result})
    end)

    receive do
      {^result_ref, {_output, 0}} -> {:ok, true}
      {^result_ref, {_output, _status}} -> {:ok, false}
    after
      1_000 -> :timeout
    end
  end

  defp with_unrelated_process(fun) do
    fixture = start_unrelated_process()
    {port, _monitor_ref, os_pid, _completion} = fixture

    try do
      fun.(port, os_pid)
    after
      complete_unrelated_process_cleanup(fixture)
    end
  end

  defp start_unrelated_process do
    sleep = System.find_executable("sleep") || "/bin/sleep"
    port = Port.open({:spawn_executable, sleep}, [:exit_status, args: ["60"]])
    {:os_pid, os_pid} = Port.info(port, :os_pid)
    monitor_ref = :erlang.monitor(:port, port)
    completion = new_fixture_completion()

    on_exit(fn ->
      fallback_cleanup_unrelated_process(port, os_pid, completion)
    end)

    {port, monitor_ref, os_pid, completion}
  end

  defp complete_unrelated_process_cleanup({port, monitor_ref, os_pid, completion}) do
    assert cleanup_unrelated_process(port, monitor_ref, os_pid)
    assert_unrelated_process_reaped(port, monitor_ref, os_pid)
    :atomics.put(completion, 1, 1)
  end

  defp cleanup_unrelated_process(port, monitor_ref, os_pid) do
    process_dead? = terminate_unrelated_process(port, os_pid)
    port_reaped? = await_fixture_port_down(port, monitor_ref, @fixture_kill_wait_ms) == :ok
    process_dead? and port_reaped?
  end

  defp fallback_cleanup_unrelated_process(port, os_pid, completion) do
    fallback_cleanup_unrelated_process(port, os_pid, completion, &signal_os_process/2)
  end

  defp fallback_cleanup_unrelated_process(port, os_pid, completion, signal_fun) do
    if fixture_cleanup_complete?(completion) do
      :already_complete
    else
      monitor_ref = :erlang.monitor(:port, port)

      case Port.info(port, :os_pid) do
        {:os_pid, ^os_pid} ->
          process_dead? = terminate_unrelated_process(port, os_pid, signal_fun)
          port_reaped? = await_fixture_port_down(port, monitor_ref, @fixture_kill_wait_ms) == :ok
          {:active_cleanup, process_dead? and port_reaped?}

        port_pid ->
          :erlang.demonitor(monitor_ref, [:flush])
          flush_exact_fixture_port_messages(port, monitor_ref)
          {:not_owned, port_pid}
      end
    end
  end

  defp terminate_unrelated_process(port, os_pid) do
    terminate_unrelated_process(port, os_pid, &signal_os_process/2)
  end

  defp terminate_unrelated_process(port, os_pid, signal_fun) do
    case os_process_alive_result(os_pid) do
      {:ok, false} -> true
      _result -> terminate_live_unrelated_process(port, os_pid, signal_fun)
    end
  end

  defp terminate_live_unrelated_process(port, os_pid, signal_fun) do
    case signal_exact_fixture_process(port, os_pid, "TERM", signal_fun) do
      {:signaled, _result} -> wait_for_term_or_kill(port, os_pid, signal_fun)
      {:not_owned, _port_pid} -> false
    end
  end

  defp wait_for_term_or_kill(port, os_pid, signal_fun) do
    if wait_for_os_process_exit(os_pid, @fixture_term_wait_ms) do
      true
    else
      case signal_exact_fixture_process(port, os_pid, "KILL", signal_fun) do
        {:signaled, _result} -> wait_for_os_process_exit(os_pid, @fixture_kill_wait_ms)
        {:not_owned, _port_pid} -> false
      end
    end
  end

  defp signal_exact_fixture_process(port, os_pid, signal, signal_fun) do
    case Port.info(port, :os_pid) do
      {:os_pid, ^os_pid} -> {:signaled, signal_fun.(os_pid, signal)}
      port_pid -> {:not_owned, port_pid}
    end
  end

  defp signal_os_process(os_pid, signal) do
    owner = self()
    result_ref = make_ref()

    spawn(fn ->
      result =
        System.cmd(kill_path(), ["-#{signal}", Integer.to_string(os_pid)], stderr_to_stdout: true, env: %{})

      send(owner, {result_ref, result})
    end)

    receive do
      {^result_ref, result} -> result
    after
      1_000 -> :timeout
    end
  end

  defp wait_for_os_process_exit(os_pid, timeout) do
    wait_until(
      fn ->
        case os_process_alive_result(os_pid) do
          {:ok, false} -> true
          _result -> nil
        end
      end,
      timeout
    ) == true
  end

  defp closed_test_port do
    executable = System.find_executable("true") || "/usr/bin/true"
    port = Port.open({:spawn_executable, executable}, [:exit_status])
    monitor_ref = :erlang.monitor(:port, port)
    assert await_fixture_port_down(port, monitor_ref, @fixture_kill_wait_ms) == :ok
    assert Port.info(port) == nil
    port
  end

  defp new_fixture_completion do
    :atomics.new(1, [])
  end

  defp fixture_cleanup_complete?(completion) do
    :atomics.get(completion, 1) == 1
  end

  defp await_fixture_port_down(port, monitor_ref, timeout) do
    deadline = System.monotonic_time(:millisecond) + timeout
    await_fixture_port_down_until(port, monitor_ref, deadline)
  end

  defp await_fixture_port_down_until(port, monitor_ref, deadline) do
    remaining = deadline - System.monotonic_time(:millisecond)

    if remaining <= 0 do
      :timeout
    else
      receive do
        {^port, {:data, _data}} ->
          await_fixture_port_down_until(port, monitor_ref, deadline)

        {^port, {:exit_status, _status}} ->
          await_fixture_port_down_until(port, monitor_ref, deadline)

        {:EXIT, ^port, _reason} ->
          await_fixture_port_down_until(port, monitor_ref, deadline)

        {:DOWN, ^monitor_ref, :port, ^port, _reason} ->
          flush_exact_fixture_port_messages(port, monitor_ref)
          :ok
      after
        remaining -> :timeout
      end
    end
  end

  defp flush_exact_fixture_port_messages(port, monitor_ref) do
    receive do
      {^port, {:data, _data}} -> flush_exact_fixture_port_messages(port, monitor_ref)
      {^port, {:exit_status, _status}} -> flush_exact_fixture_port_messages(port, monitor_ref)
      {:EXIT, ^port, _reason} -> flush_exact_fixture_port_messages(port, monitor_ref)
      {:DOWN, ^monitor_ref, :port, ^port, _reason} -> flush_exact_fixture_port_messages(port, monitor_ref)
    after
      0 -> :ok
    end
  end

  defp assert_unrelated_process_reaped(port, monitor_ref, os_pid) do
    refute os_process_alive?(os_pid)
    assert Port.info(port) == nil
    refute port in linked_ports()

    {:messages, messages} = Process.info(self(), :messages)
    refute Enum.any?(messages, &exact_fixture_port_message?(&1, port, monitor_ref))
  end

  defp exact_fixture_port_message?({port, {:data, _data}}, port, _monitor_ref), do: true
  defp exact_fixture_port_message?({port, {:exit_status, _status}}, port, _monitor_ref), do: true
  defp exact_fixture_port_message?({:EXIT, port, _reason}, port, _monitor_ref), do: true

  defp exact_fixture_port_message?({:DOWN, monitor_ref, :port, port, _reason}, port, monitor_ref), do: true

  defp exact_fixture_port_message?(_message, _port, _monitor_ref), do: false

  defp refute_port_messages do
    {:messages, messages} = Process.info(self(), :messages)

    refute Enum.any?(messages, fn
             {port, {:data, _data}} when is_port(port) -> true
             {port, {:exit_status, _status}} when is_port(port) -> true
             {:EXIT, port, _reason} when is_port(port) -> true
             {:DOWN, _ref, :port, port, _reason} when is_port(port) -> true
             _message -> false
           end)
  end

  defp linked_ports do
    {:links, links} = Process.info(self(), :links)
    Enum.filter(links, &is_port/1)
  end

  defp kill_path, do: System.find_executable("kill") || "/bin/kill"

  defp tmp_path(prefix) do
    Path.join(System.tmp_dir!(), "#{prefix}_#{System.unique_integer([:positive])}")
  end
end
