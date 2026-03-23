defmodule Jido.Browser.Adapters.Web.PoolRuntime do
  @moduledoc false
  @behaviour Jido.Browser.WarmPool.Runtime

  alias Jido.Browser.Adapters.Web.CLI

  @type worker_state :: %{
          session_id: String.t(),
          profile: String.t(),
          profile_path: String.t(),
          binary: String.t(),
          runtime: map()
        }

  @impl true
  def start_worker(%{worker_opts: worker_opts}) do
    session_id = "web-pool-#{System.unique_integer([:positive])}"
    profile = build_profile_name(worker_opts)
    profile_path = CLI.profile_path(profile)
    binary = Keyword.fetch!(worker_opts, :binary)
    timeout = Keyword.fetch!(worker_opts, :timeout)

    worker_opts = worker_opts |> Keyword.put(:binary, binary) |> Keyword.put(:timeout, timeout)

    with :ok <- CLI.warm_profile(profile, worker_opts) do
      {:ok,
       %{
         session_id: session_id,
         profile: profile,
         profile_path: profile_path,
         binary: binary,
         runtime: %{
           transport: :web_cli,
           profile: profile,
           profile_path: profile_path,
           session_id: session_id
         }
       }}
    end
  end

  @impl true
  def command(%{profile: profile, binary: binary}, payload, timeout) do
    CLI.execute(profile, payload, binary: binary, timeout: timeout)
  end

  @impl true
  def shutdown_worker(%{profile_path: profile_path}) do
    _ = File.rm_rf(profile_path)
    :ok
  end

  @impl true
  def health_check(%{profile_path: profile_path, binary: binary}) do
    cond do
      not File.exists?(binary) -> {:error, :binary_missing}
      not File.dir?(profile_path) -> {:error, :profile_missing}
      true -> :ok
    end
  end

  defp build_profile_name(worker_opts) do
    pool_hash = :erlang.phash2(worker_opts[:pool_name] || :default)
    prefix = Keyword.get(worker_opts, :profile_prefix, "jido-browser-web-pool")
    "#{prefix}-#{pool_hash}-#{System.unique_integer([:positive])}"
  end
end
