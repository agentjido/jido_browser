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
    stderr_path = tmp_path("browsey_stderr")

    try do
      executable
      |> run_executable(args, stderr_path, timeout, max_output_bytes)
      |> format_result(stderr_path)
    after
      File.rm(stderr_path)
    end
  end

  @spec running_as_root?() :: boolean()
  def running_as_root? do
    System.cmd("id", ["-u"], env: %{}) == {"0\n", 0}
  end

  defp run_executable(executable, args, stderr_path, timeout, max_output_bytes) do
    port =
      Port.open({:spawn_executable, executable}, [
        :binary,
        :exit_status,
        :use_stdio,
        args: args ++ ["--stderr", stderr_path],
        env: [{~c"BROWSEY_STDERR_PATH", String.to_charlist(stderr_path)}]
      ])

    {:os_pid, os_pid} = Port.info(port, :os_pid)
    deadline = System.monotonic_time(:millisecond) + timeout
    collect_exit(port, os_pid, deadline, max_output_bytes, [], 0)
  end

  defp collect_exit(port, os_pid, deadline, max_output_bytes, stdout, observed_bytes) do
    timeout = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {^port, {:data, data}} ->
        observed_bytes = observed_bytes + byte_size(data)

        if max_output_bytes != :infinity and observed_bytes > max_output_bytes do
          case terminate_and_reap(port, os_pid) do
            {:ok, _exit_status} -> {:too_large, observed_bytes}
            {:error, reason} -> {:cleanup_failed, reason, [], observed_bytes}
          end
        else
          collect_exit(port, os_pid, deadline, max_output_bytes, [data | stdout], observed_bytes)
        end

      {^port, {:exit_status, status}} ->
        {:exit_status, status, Enum.reverse(stdout), observed_bytes}
    after
      timeout ->
        case terminate_and_reap(port, os_pid) do
          {:ok, _exit_status} -> {:timeout, 28, Enum.reverse(stdout), observed_bytes}
          {:error, reason} -> {:cleanup_failed, reason, Enum.reverse(stdout), observed_bytes}
        end
    end
  end

  defp terminate_and_reap(port, os_pid) do
    term_result = signal_exact_port_process(port, os_pid, "TERM")

    case {term_result, await_exit(port, @term_wait_ms)} do
      {_term_result, {:ok, exit_status}} ->
        {:ok, exit_status}

      {term_result, :timeout} ->
        kill_and_reap(port, os_pid, term_result)
    end
  end

  defp kill_and_reap(port, os_pid, term_result) do
    kill_result = signal_exact_port_process(port, os_pid, "KILL")

    case await_exit(port, @kill_wait_ms) do
      {:ok, exit_status} ->
        {:ok, exit_status}

      :timeout ->
        cleanup_failure(port, os_pid, %{
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

  defp await_exit(port, wait_ms) do
    deadline = System.monotonic_time(:millisecond) + wait_ms
    await_exit(port, nil, deadline)
  end

  defp await_exit(port, exit_status, deadline) do
    if exit_status != nil and Port.info(port) == nil do
      {:ok, exit_status}
    else
      remaining = deadline - System.monotonic_time(:millisecond)

      if remaining <= 0 do
        :timeout
      else
        receive do
          {^port, {:data, _data}} -> await_exit(port, exit_status, deadline)
          {^port, {:exit_status, status}} -> await_exit(port, status, deadline)
        after
          min(remaining, @cleanup_poll_ms) -> await_exit(port, exit_status, deadline)
        end
      end
    end
  end

  defp cleanup_failure(port, os_pid, reason) do
    port_open? = Port.info(port) != nil
    close_port(port)

    {:error,
     {:process_cleanup_failed,
      %{
        os_pid: os_pid,
        port_open?: port_open?,
        reason: reason
      }}}
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
