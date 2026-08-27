defmodule Jido.Browser.Vendor.BrowseyHttp.Util.Exec do
  @moduledoc false

  @term_wait_ms 250
  @kill_wait_ms 1_000
  @cleanup_poll_ms 10

  @type max_output_bytes :: non_neg_integer() | :infinity

  @spec exec(Path.t(), [String.t()], timeout(), max_output_bytes()) ::
          {:ok, [{:stdout | :stderr, [binary()]}]} | {:error, Keyword.t()}
  def exec(executable, args, timeout, max_output_bytes \\ :infinity)
      when is_binary(executable) and is_list(args) do
    exec_with_pid_lookup(executable, args, timeout, max_output_bytes, &Port.info(&1, :os_pid))
  end

  if Mix.env() == :test do
    @doc false
    @spec __test_exec__(
            Path.t(),
            [String.t()],
            timeout(),
            max_output_bytes(),
            (port() -> {:os_pid, non_neg_integer()} | nil)
          ) :: {:ok, [{:stdout | :stderr, [binary()]}]} | {:error, Keyword.t()}
    def __test_exec__(executable, args, timeout, max_output_bytes, pid_lookup)
        when is_binary(executable) and is_list(args) and is_function(pid_lookup, 1) do
      # This seam is compiled only in the project test build. It forces the post-open
      # PID race without an application environment or process dictionary hook.
      exec_with_pid_lookup(executable, args, timeout, max_output_bytes, pid_lookup)
    end
  end

  defp exec_with_pid_lookup(executable, args, timeout, max_output_bytes, pid_lookup) do
    stderr_path = tmp_path("browsey_stderr")

    try do
      executable
      |> run_executable(args, stderr_path, timeout, max_output_bytes, pid_lookup)
      |> format_result(stderr_path)
    after
      File.rm(stderr_path)
    end
  end

  @spec running_as_root?() :: boolean()
  def running_as_root? do
    System.cmd("id", ["-u"], env: %{}) == {"0\n", 0}
  end

  defp run_executable(executable, args, stderr_path, timeout, max_output_bytes, pid_lookup) do
    port =
      Port.open({:spawn_executable, executable}, [
        :binary,
        :exit_status,
        :use_stdio,
        args: args ++ ["--stderr", stderr_path],
        env: [{~c"BROWSEY_STDERR_PATH", String.to_charlist(stderr_path)}]
      ])

    monitor_ref = :erlang.monitor(:port, port)

    case pid_lookup.(port) do
      {:os_pid, os_pid} ->
        deadline = System.monotonic_time(:millisecond) + timeout
        collect_exit(port, monitor_ref, os_pid, deadline, max_output_bytes, [], 0)

      nil ->
        # The closed port can still have ordered data and exit messages in this mailbox.
        # Drain them without a signal because an exact process identity is no longer available.
        collect_exited_port(port, monitor_ref, max_output_bytes, [], 0, false)
    end
  end

  defp collect_exited_port(port, monitor_ref, max_output_bytes, stdout, observed_bytes, output_too_large?) do
    receive do
      {^port, {:data, data}} ->
        observed_bytes = observed_bytes + byte_size(data)
        output_too_large? = output_too_large?(max_output_bytes, observed_bytes)
        stdout = if output_too_large?, do: [], else: [data | stdout]

        collect_exited_port(port, monitor_ref, max_output_bytes, stdout, observed_bytes, output_too_large?)

      {^port, {:exit_status, _status}} when output_too_large? ->
        finish_exit_result(port, monitor_ref, nil, {:too_large, observed_bytes}, [], observed_bytes)

      {^port, {:exit_status, status}} ->
        stdout = Enum.reverse(stdout)

        finish_exit_result(
          port,
          monitor_ref,
          nil,
          {:exit_status, status, stdout, observed_bytes},
          stdout,
          observed_bytes
        )
    after
      @kill_wait_ms ->
        {:error, reason} =
          cleanup_failure(port, monitor_ref, nil, %{
            reason: :exit_status_timeout
          })

        {:cleanup_failed, reason, Enum.reverse(stdout), observed_bytes}
    end
  end

  defp output_too_large?(:infinity, _observed_bytes), do: false
  defp output_too_large?(max_output_bytes, observed_bytes), do: observed_bytes > max_output_bytes

  defp collect_exit(port, monitor_ref, os_pid, deadline, max_output_bytes, stdout, observed_bytes) do
    timeout = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {^port, {:data, data}} ->
        observed_bytes = observed_bytes + byte_size(data)

        if max_output_bytes != :infinity and observed_bytes > max_output_bytes do
          case terminate_and_reap(port, monitor_ref, os_pid) do
            {:ok, _exit_status} -> {:too_large, observed_bytes}
            {:error, reason} -> {:cleanup_failed, reason, [], observed_bytes}
          end
        else
          collect_exit(port, monitor_ref, os_pid, deadline, max_output_bytes, [data | stdout], observed_bytes)
        end

      {^port, {:exit_status, status}} ->
        stdout = Enum.reverse(stdout)

        finish_exit_result(
          port,
          monitor_ref,
          os_pid,
          {:exit_status, status, stdout, observed_bytes},
          stdout,
          observed_bytes
        )
    after
      timeout ->
        case terminate_and_reap(port, monitor_ref, os_pid) do
          {:ok, _exit_status} -> {:timeout, 28, Enum.reverse(stdout), observed_bytes}
          {:error, reason} -> {:cleanup_failed, reason, Enum.reverse(stdout), observed_bytes}
        end
    end
  end

  defp finish_exit_result(port, monitor_ref, os_pid, result, stdout, observed_bytes) do
    deadline = System.monotonic_time(:millisecond) + @kill_wait_ms

    case await_port_down(port, monitor_ref, deadline) do
      :ok ->
        result

      :timeout ->
        {:error, reason} =
          cleanup_failure(port, monitor_ref, os_pid, %{
            reason: :port_reap_timeout
          })

        {:cleanup_failed, reason, stdout, observed_bytes}
    end
  end

  defp terminate_and_reap(port, monitor_ref, os_pid) do
    term_result = signal_exact_port_process(port, os_pid, "TERM")

    case {term_result, await_exit(port, monitor_ref, @term_wait_ms)} do
      {_term_result, {:ok, exit_status}} ->
        {:ok, exit_status}

      {term_result, {:timeout, exit_status}} ->
        kill_and_reap(port, monitor_ref, os_pid, term_result, exit_status)
    end
  end

  defp kill_and_reap(port, monitor_ref, os_pid, term_result, exit_status) do
    kill_result = signal_exact_port_process(port, os_pid, "KILL")

    case await_exit(port, monitor_ref, @kill_wait_ms, exit_status) do
      {:ok, exit_status} ->
        {:ok, exit_status}

      {:timeout, _exit_status} ->
        cleanup_failure(port, monitor_ref, os_pid, %{
          kill_result: kill_result,
          reason: :kill_timeout,
          term_result: term_result
        })
    end
  end

  defp signal_exact_port_process(port, os_pid, signal) do
    case Port.info(port, :os_pid) do
      {:os_pid, ^os_pid} -> run_kill(port, os_pid, signal)
      nil -> :ok
      {:os_pid, other_pid} -> {:error, {:port_pid_changed, os_pid, other_pid}}
    end
  end

  defp run_kill(port, os_pid, signal) do
    case System.cmd(kill_path(), ["-#{signal}", Integer.to_string(os_pid)], stderr_to_stdout: true, env: %{}) do
      {_output, 0} ->
        :ok

      {output, status} ->
        case Port.info(port, :os_pid) do
          nil -> :ok
          {:os_pid, ^os_pid} -> {:error, {:signal_failed, signal, os_pid, status, String.trim(output)}}
          {:os_pid, other_pid} -> {:error, {:port_pid_changed, os_pid, other_pid}}
        end
    end
  rescue
    error -> {:error, {:signal_failed, signal, os_pid, error}}
  end

  defp await_exit(port, monitor_ref, wait_ms, exit_status \\ nil) do
    deadline = System.monotonic_time(:millisecond) + wait_ms
    await_exit_until(port, monitor_ref, exit_status, deadline)
  end

  defp await_exit_until(port, monitor_ref, exit_status, deadline) do
    if exit_status != nil do
      case await_port_down(port, monitor_ref, deadline) do
        :ok -> {:ok, exit_status}
        :timeout -> {:timeout, exit_status}
      end
    else
      remaining = deadline - System.monotonic_time(:millisecond)

      if remaining <= 0 do
        {:timeout, nil}
      else
        receive do
          {^port, {:data, _data}} -> await_exit_until(port, monitor_ref, nil, deadline)
          {^port, {:exit_status, status}} -> await_exit_until(port, monitor_ref, status, deadline)
        after
          min(remaining, @cleanup_poll_ms) -> await_exit_until(port, monitor_ref, nil, deadline)
        end
      end
    end
  end

  # OTP sends exit_status before the port monitor DOWN. The port link EXIT signal
  # is also delivered before DOWN. DOWN is therefore a safe mailbox barrier.
  defp await_port_down(port, monitor_ref, deadline) do
    remaining = deadline - System.monotonic_time(:millisecond)

    if remaining <= 0 do
      :timeout
    else
      receive do
        {:DOWN, ^monitor_ref, :port, ^port, _reason} ->
          flush_exact_port_exit(port)
          :ok
      after
        remaining -> :timeout
      end
    end
  end

  defp flush_exact_port_exit(port) do
    receive do
      {:EXIT, ^port, _reason} -> flush_exact_port_exit(port)
    after
      0 -> :ok
    end
  end

  defp cleanup_failure(port, monitor_ref, os_pid, reason) do
    port_open? = Port.info(port) != nil
    close_port(port)
    cleanup_deadline = System.monotonic_time(:millisecond) + @kill_wait_ms
    flush_closed_port(port, monitor_ref, cleanup_deadline)

    {:error,
     {:process_cleanup_failed,
      %{
        os_pid: os_pid,
        port_open?: port_open?,
        reason: reason
      }}}
  end

  defp flush_closed_port(port, monitor_ref, deadline) do
    remaining = deadline - System.monotonic_time(:millisecond)

    if remaining <= 0 do
      :erlang.demonitor(monitor_ref, [:flush])
      :timeout
    else
      receive do
        {^port, {:data, _data}} ->
          flush_closed_port(port, monitor_ref, deadline)

        {^port, {:exit_status, _status}} ->
          flush_closed_port(port, monitor_ref, deadline)

        {:DOWN, ^monitor_ref, :port, ^port, _reason} ->
          flush_exact_port_exit(port)
          :ok
      after
        remaining ->
          :erlang.demonitor(monitor_ref, [:flush])
          :timeout
      end
    end
  end

  defp format_result({:exit_status, 0, stdout, _observed_bytes}, stderr_path) do
    {:ok, [stdout: stdout, stderr: [read_output(stderr_path)]]}
  end

  defp format_result({:exit_status, status, stdout, observed_bytes}, stderr_path) do
    {:error,
     [
       exit_status: status,
       observed_bytes: observed_bytes,
       stdout: stdout,
       stderr: [read_output(stderr_path)]
     ]}
  end

  defp format_result({:timeout, status, stdout, observed_bytes}, stderr_path) do
    {:error,
     [
       exit_status: status,
       observed_bytes: observed_bytes,
       stdout: stdout,
       stderr: [read_output(stderr_path)]
     ]}
  end

  defp format_result({:too_large, observed_bytes}, stderr_path) do
    {:error,
     [
       exit_status: 63,
       observed_bytes: observed_bytes,
       response_too_large?: true,
       stdout: [],
       stderr: [read_output(stderr_path)]
     ]}
  end

  defp format_result({:cleanup_failed, reason, stdout, observed_bytes}, stderr_path) do
    {:error,
     [
       cleanup_error: reason,
       exit_status: 1,
       observed_bytes: observed_bytes,
       stdout: stdout,
       stderr: [read_output(stderr_path)]
     ]}
  end

  defp read_output(path) do
    case File.read(path) do
      {:ok, output} -> output
      {:error, _reason} -> ""
    end
  end

  defp tmp_path(prefix) do
    Path.join(System.tmp_dir!(), "#{prefix}_#{System.unique_integer([:positive])}")
  end

  defp kill_path do
    System.find_executable("kill") || "/bin/kill"
  end

  defp close_port(port) do
    Port.close(port)
  rescue
    ArgumentError -> :ok
  end
end
