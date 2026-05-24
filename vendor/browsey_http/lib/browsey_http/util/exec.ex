defmodule Jido.Browser.Vendor.BrowseyHttp.Util.Exec do
  @moduledoc false

  @spec exec(String.t(), timeout()) ::
          {:ok, [{:stdout | :stderr, [binary()]}]} | {:error, Keyword.t()}
  def exec(command, timeout) do
    stdout_path = tmp_path("browsey_stdout")
    stderr_path = tmp_path("browsey_stderr")

    try do
      command
      |> redirect_command(stdout_path, stderr_path)
      |> run_shell(timeout)
      |> format_result(stdout_path, stderr_path)
    after
      File.rm(stdout_path)
      File.rm(stderr_path)
    end
  end

  @spec running_as_root?() :: boolean()
  def running_as_root? do
    System.cmd("id", ["-u"], env: %{}) == {"0\n", 0}
  end

  defp run_shell(command, timeout) do
    port =
      Port.open({:spawn_executable, shell_path()}, [
        :binary,
        :exit_status,
        args: ["-c", command]
      ])

    collect_exit(port, timeout)
  end

  defp collect_exit(port, timeout) do
    receive do
      {^port, {:exit_status, status}} ->
        {:exit_status, status}
    after
      timeout ->
        Port.close(port)
        {:timeout, 28}
    end
  end

  defp format_result({:exit_status, 0}, stdout_path, stderr_path) do
    {:ok, [stdout: [read_output(stdout_path)], stderr: [read_output(stderr_path)]]}
  end

  defp format_result({:exit_status, status}, stdout_path, stderr_path) do
    {:error,
     [
       exit_status: status,
       stdout: [read_output(stdout_path)],
       stderr: [read_output(stderr_path)]
     ]}
  end

  defp format_result({:timeout, status}, stdout_path, stderr_path) do
    {:error,
     [
       exit_status: status,
       stdout: [read_output(stdout_path)],
       stderr: [read_output(stderr_path)]
     ]}
  end

  defp redirect_command(command, stdout_path, stderr_path) do
    "#{command} > #{shell_quote(stdout_path)} 2> #{shell_quote(stderr_path)}"
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

  defp shell_path do
    System.find_executable("sh") || "/bin/sh"
  end

  defp shell_quote(value) do
    "'" <> String.replace(value, "'", "'\\''") <> "'"
  end
end
