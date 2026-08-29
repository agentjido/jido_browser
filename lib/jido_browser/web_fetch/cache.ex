defmodule Jido.Browser.WebFetch.Cache do
  @moduledoc false

  @cache_table :jido_browser_web_fetch_cache

  @doc false
  @spec clear() :: :ok
  def clear do
    case :ets.whereis(@cache_table) do
      :undefined ->
        :ok

      table ->
        :ets.delete_all_objects(table)
        :ok
    end
  end

  @doc false
  @spec fetch(String.t(), keyword()) :: {:ok, map()} | :miss
  def fetch(url, opts) do
    if opts[:cache] do
      ensure_cache_table!()
      lookup_cached_result(cache_key(url, opts), System.system_time(:millisecond))
    else
      :miss
    end
  end

  @doc false
  @spec store(String.t(), keyword(), map()) :: :ok
  def store(url, opts, result) do
    if opts[:cache] do
      ensure_cache_table!()

      expires_at = System.system_time(:millisecond) + max(opts[:cache_ttl_ms], 0)
      :ets.insert(@cache_table, {cache_key(url, opts), expires_at, result})
    end

    :ok
  end

  defp lookup_cached_result(key, now) do
    case :ets.lookup(@cache_table, key) do
      [{_key, expires_at, result}] -> handle_cached_result(key, expires_at, result, now)
      [] -> :miss
    end
  end

  defp handle_cached_result(_key, expires_at, result, now) when expires_at > now do
    {:ok, Map.put(result, :cached, true)}
  end

  defp handle_cached_result(key, _expires_at, _result, _now) do
    :ets.delete(@cache_table, key)
    :miss
  end

  defp ensure_cache_table! do
    case :ets.whereis(@cache_table) do
      :undefined ->
        try do
          :ets.new(@cache_table, [:named_table, :set, :public, read_concurrency: true, write_concurrency: true])
        rescue
          ArgumentError -> @cache_table
        end

      table ->
        table
    end
  end

  defp cache_key(url, opts) do
    {:jido_browser_web_fetch, url, opts[:format], opts[:selector], opts[:allowed_domains], opts[:blocked_domains],
     opts[:focus_terms], opts[:focus_window], opts[:max_content_tokens], opts[:max_response_bytes], opts[:citations],
     opts[:extractous], opts[:backend], opts[:req], opts[:allow_private_network]}
  end
end
