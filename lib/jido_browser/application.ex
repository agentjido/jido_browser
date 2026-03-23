defmodule Jido.Browser.Application do
  @moduledoc false

  use Application

  @required_processes [
    Jido.Browser.AgentBrowser.SessionTreeSupervisor,
    Jido.Browser.AgentBrowser.Registry,
    Jido.Browser.AgentBrowser.SessionSupervisor,
    Jido.Browser.WarmPool.RootSupervisor,
    Jido.Browser.WarmPool.Registry,
    Jido.Browser.WarmPool.Supervisor
  ]

  @boot_poll_interval 10
  @default_boot_timeout 5_000

  @impl true
  def start(_type, _args) do
    children = [
      Jido.Browser.AgentBrowser.SessionTreeSupervisor,
      Jido.Browser.WarmPool.RootSupervisor
    ]

    Supervisor.start_link(children,
      strategy: :rest_for_one,
      name: Jido.Browser.Supervisor
    )
  end

  @doc false
  @spec ensure_started(timeout()) :: :ok | {:error, term()}
  def ensure_started(timeout \\ @default_boot_timeout) do
    case do_ensure_started(timeout) do
      :ok ->
        :ok

      {:error, {:startup_timeout, _missing} = reason} ->
        if app_started?(:jido_browser) do
          restart_application(timeout)
        else
          {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp await_processes(_deadline, []), do: :ok

  defp await_processes(deadline, process_names) do
    missing = Enum.reject(process_names, &process_running?/1)

    cond do
      missing == [] ->
        :ok

      System.monotonic_time(:millisecond) >= deadline ->
        {:error, {:startup_timeout, missing}}

      true ->
        Process.sleep(@boot_poll_interval)
        await_processes(deadline, missing)
    end
  end

  defp process_running?(name) do
    case Process.whereis(name) do
      pid when is_pid(pid) -> Process.alive?(pid)
      nil -> false
    end
  end

  defp do_ensure_started(timeout) do
    deadline = System.monotonic_time(:millisecond) + timeout

    case Application.ensure_all_started(:jido_browser) do
      {:ok, _apps} -> await_processes(deadline, @required_processes)
      {:error, reason} -> {:error, reason}
    end
  end

  defp restart_application(timeout) do
    _ = Application.stop(:jido_browser)
    do_ensure_started(timeout)
  end

  defp app_started?(app) do
    Enum.any?(Application.started_applications(), fn {started_app, _description, _vsn} ->
      started_app == app
    end)
  end
end
