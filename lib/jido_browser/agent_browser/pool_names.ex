defmodule Jido.Browser.AgentBrowser.PoolNames do
  @moduledoc false

  @registry Jido.Browser.AgentBrowser.PoolRegistry

  @tree :tree
  @manager :manager
  @session_supervisor :session_supervisor
  @lease_supervisor :lease_supervisor
  @cleanup_supervisor :cleanup_supervisor

  @type pool_name :: term()
  @type component ::
          :tree
          | :manager
          | :session_supervisor
          | :lease_supervisor
          | :cleanup_supervisor

  @doc false
  @spec tree(pool_name()) :: {:via, Registry, {module(), term()}}
  def tree(name), do: via({@tree, name})

  @doc false
  @spec manager(pool_name()) :: {:via, Registry, {module(), term()}}
  def manager(name), do: via({@manager, name})

  @doc false
  @spec session_supervisor(pool_name()) :: {:via, Registry, {module(), term()}}
  def session_supervisor(name), do: via({@session_supervisor, name})

  @doc false
  @spec lease_supervisor(pool_name()) :: {:via, Registry, {module(), term()}}
  def lease_supervisor(name), do: via({@lease_supervisor, name})

  @doc false
  @spec cleanup_supervisor(pool_name()) :: {:via, Registry, {module(), term()}}
  def cleanup_supervisor(name), do: via({@cleanup_supervisor, name})

  @doc false
  @spec resolve_tree(term()) :: {:ok, pid()} | {:error, :pool_not_found}
  def resolve_tree(pid) when is_pid(pid) do
    case resolve_name_for_pid(pid, @tree) do
      {:ok, _name} -> {:ok, pid}
      :error -> resolve_registered_pid(pid, @manager, &resolve_tree/1)
    end
  end

  def resolve_tree(name) do
    resolve_key({@tree, name})
  end

  @doc false
  @spec resolve_manager(term()) :: {:ok, pid()} | {:error, :pool_not_found}
  def resolve_manager(pid) when is_pid(pid) do
    case resolve_name_for_pid(pid, @manager) do
      {:ok, _name} -> {:ok, pid}
      :error -> resolve_registered_pid(pid, @tree, &resolve_manager/1)
    end
  end

  def resolve_manager(name) do
    resolve_key({@manager, name})
  end

  @doc false
  @spec resolve_name_for_pid(pid(), component()) :: {:ok, pool_name()} | :error
  def resolve_name_for_pid(pid, component) when is_pid(pid) do
    @registry
    |> safe_registry_keys(pid)
    |> Enum.find_value(:error, fn
      {^component, name} -> {:ok, name}
      _other -> nil
    end)
  end

  @doc false
  @spec via(term()) :: {:via, Registry, {module(), term()}}
  def via(key), do: {:via, Registry, {@registry, key}}

  defp resolve_registered_pid(pid, component, resolver) do
    case resolve_name_for_pid(pid, component) do
      {:ok, name} -> resolver.(name)
      :error -> {:error, :pool_not_found}
    end
  end

  defp resolve_key(key) do
    case safe_registry_lookup(@registry, key) do
      [{pid, _value}] -> {:ok, pid}
      [] -> {:error, :pool_not_found}
    end
  end

  defp safe_registry_lookup(registry, key) do
    Registry.lookup(registry, key)
  catch
    :exit, _reason ->
      []
  end

  defp safe_registry_keys(registry, pid) do
    Registry.keys(registry, pid)
  catch
    :exit, _reason ->
      []
  end
end
