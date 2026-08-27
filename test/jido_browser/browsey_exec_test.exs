defmodule Jido.Browser.BrowseyExecTest do
  use ExUnit.Case, async: false

  alias Jido.Browser.Vendor.BrowseyHttp.Util.Exec

  test "keeps stdout and stderr separate on normal success" do
    shell = System.find_executable("sh") || "/bin/sh"

    assert {:ok, result} =
             Exec.exec(
               shell,
               ["-c", ~s(printf normal; printf diagnostic > "$2"), "browsey-exec-test"],
               1_000
             )

    assert IO.iodata_to_binary(result[:stdout]) == "normal"
    assert IO.iodata_to_binary(result[:stderr]) == "diagnostic"
  end

  test "terminates and reaps the exact port process on timeout" do
    shell = System.find_executable("sh") || "/bin/sh"
    pid_path = tmp_path("browsey_timeout_pid")
    File.rm(pid_path)
    on_exit(fn -> File.rm(pid_path) end)

    task =
      Task.async(fn ->
        Exec.exec(
          shell,
          [
            "-c",
            ~s(trap '' TERM; printf "%s" "$$" > "$0"; printf timeout > "$2"; while :; do :; done),
            pid_path
          ],
          100
        )
      end)

    port = wait_for_task_port(task.pid)
    {:os_pid, os_pid} = Port.info(port, :os_pid)
    assert wait_for_file(pid_path)
    assert pid_path |> File.read!() |> String.to_integer() == os_pid

    assert {:error, result} = Task.await(task, 2_000)
    assert result[:exit_status] == 28
    assert IO.iodata_to_binary(result[:stderr]) == "timeout"
    assert Port.info(port) == nil
    refute os_process_alive?(os_pid)
  end

  defp wait_for_task_port(task_pid), do: wait_until(fn -> task_port(task_pid) end, 1_000)

  defp task_port(task_pid) do
    case Process.info(task_pid, :links) do
      {:links, links} -> Enum.find(links, &is_port/1)
      nil -> nil
    end
  end

  defp wait_for_file(path) do
    wait_until(fn -> if File.exists?(path), do: true end, 1_000)
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

  defp os_process_alive?(pid) do
    case System.cmd(kill_path(), ["-0", Integer.to_string(pid)], stderr_to_stdout: true, env: %{}) do
      {_output, 0} -> true
      {_output, _status} -> false
    end
  end

  defp kill_path, do: System.find_executable("kill") || "/bin/kill"

  defp tmp_path(prefix) do
    Path.join(System.tmp_dir!(), "#{prefix}_#{System.unique_integer([:positive])}")
  end
end
