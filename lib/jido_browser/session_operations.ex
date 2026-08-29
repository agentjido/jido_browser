defmodule Jido.Browser.SessionOperations do
  @moduledoc false

  alias Jido.Browser.Error
  alias Jido.Browser.PoolAdapter
  alias Jido.Browser.Result
  alias Jido.Browser.Session
  alias Jido.Browser.WarmPool.Names

  @default_adapter Jido.Browser.Adapters.AgentBrowser
  @default_timeout 30_000
  @supported_extract_formats [:markdown, :html, :text]

  @doc false
  @spec start_session(keyword()) :: {:ok, Session.t()} | {:error, term()}
  def start_session(opts) do
    with {:ok, adapter} <- resolve_session_adapter(opts),
         :ok <- validate_pool_capability(adapter, opts) do
      case adapter.start_session(opts) do
        {:ok, %Session{} = session} ->
          {:ok, session}

        %Session{} = session ->
          {:ok, session}

        {:error, _reason} = error ->
          error

        other ->
          {:error, Error.adapter_error("Adapter returned invalid session result", %{adapter: adapter, result: other})}
      end
    end
  end

  @doc false
  @spec end_session(Session.t()) :: :ok | {:error, term()}
  def end_session(%Session{} = session), do: session.adapter.end_session(session)

  @doc false
  @spec navigate(Session.t(), String.t(), keyword()) ::
          {:ok, Session.t(), map()} | {:error, term()}
  def navigate(%Session{}, url, _opts) when url in [nil, ""] do
    {:error, Error.invalid_error("URL cannot be nil or empty", %{url: url})}
  end

  def navigate(%Session{} = session, url, opts) do
    session.adapter.navigate(session, url, normalize_timeout(opts))
  end

  @doc false
  @spec extract_content(Session.t(), keyword()) ::
          {:ok, Session.t(), map()} | {:error, term()}
  def extract_content(%Session{} = session, opts) do
    format = opts[:format] || :markdown

    if format in @supported_extract_formats do
      opts =
        opts
        |> Keyword.put_new(:format, :markdown)
        |> Keyword.put_new(:selector, "body")
        |> normalize_timeout()

      session.adapter.extract_content(session, opts)
    else
      {:error,
       Error.invalid_error("Unsupported extract format: #{inspect(format)}", %{
         format: format,
         supported: @supported_extract_formats
       })}
    end
  end

  @doc false
  @spec snapshot(Session.t(), keyword()) :: {:ok, Session.t(), map()} | {:error, term()}
  def snapshot(%Session{} = session, opts) do
    command_or_fallback(session, :snapshot, opts, fn ->
      selector = opts[:selector] || "body"
      max_content_length = opts[:max_content_length] || 50_000

      script = """
      (function snapshot(selector, maxContentLength) {
        const root = document.querySelector(selector) || document.body;
        return {
          url: window.location.href,
          title: document.title,
          origin: window.location.href,
          snapshot: root.innerText.substring(0, maxContentLength),
          refs: {}
        };
      })(#{Jason.encode!(selector)}, #{max_content_length})
      """

      case evaluate(session, script, opts) do
        {:ok, session, %{result: result}} when is_map(result) -> {:ok, session, Result.normalize(result)}
        other -> other
      end
    end)
  end

  defp evaluate(%Session{adapter: adapter} = session, script, opts) do
    if function_exported?(adapter, :evaluate, 3) do
      adapter.evaluate(session, script, normalize_timeout(opts))
    else
      {:error,
       Error.invalid_error(
         "Adapter #{inspect(adapter)} does not support JavaScript evaluation",
         %{adapter: adapter}
       )}
    end
  end

  defp command_or_fallback(%Session{} = session, action, opts, fallback_fun) do
    if command_supported?(session) do
      command(session, action, opts)
    else
      fallback_fun.()
    end
  end

  defp command(%Session{adapter: adapter} = session, action, opts) do
    if function_exported?(adapter, :command, 3) do
      adapter.command(session, action, normalize_timeout(opts))
    else
      {:error,
       Error.invalid_error(
         "Adapter #{inspect(adapter)} does not support #{action}",
         %{adapter: adapter, action: action}
       )}
    end
  end

  defp command_supported?(%Session{adapter: adapter}), do: function_exported?(adapter, :command, 3)

  defp configured_adapter do
    Application.get_env(:jido_browser, :adapter, @default_adapter)
  end

  defp adapter_for_pool(pool) do
    case Names.resolve_manager(pool) do
      {:ok, pid} ->
        case GenServer.call(pid, :adapter) do
          adapter when is_atom(adapter) ->
            {:ok, adapter}

          other ->
            {:error, Error.adapter_error("Warm pool adapter could not be resolved", %{pool: pool, adapter: other})}
        end

      {:error, :pool_not_found} ->
        {:error, Error.adapter_error("No warm pool available", %{pool: pool})}
    end
  catch
    :exit, reason ->
      {:error, Error.adapter_error("Failed to resolve warm pool adapter", %{pool: pool, reason: reason})}
  end

  defp resolve_session_adapter(opts) do
    case opts[:pool] do
      nil ->
        {:ok, opts[:adapter] || configured_adapter()}

      pool ->
        maybe_resolve_pool_adapter(pool, opts[:adapter])
    end
  end

  defp maybe_resolve_pool_adapter(pool, nil), do: adapter_for_pool(pool)

  defp maybe_resolve_pool_adapter(pool, explicit_adapter) do
    case adapter_for_pool(pool) do
      {:ok, pool_adapter} when pool_adapter != explicit_adapter ->
        {:error,
         Error.invalid_error(
           "Pool #{inspect(pool)} belongs to adapter #{inspect(pool_adapter)}, not #{inspect(explicit_adapter)}",
           %{pool: pool, pool_adapter: pool_adapter, adapter: explicit_adapter}
         )}

      {:ok, _pool_adapter} ->
        {:ok, explicit_adapter}

      {:error, _reason} ->
        {:ok, explicit_adapter}
    end
  end

  defp validate_pool_capability(adapter, opts) do
    if opts[:pool] && not PoolAdapter.supports_pools?(adapter) do
      {:error,
       Error.invalid_error(
         "Adapter #{inspect(adapter)} does not support pooled sessions",
         %{adapter: adapter}
       )}
    else
      :ok
    end
  end

  defp normalize_timeout(opts), do: Keyword.put_new(opts, :timeout, @default_timeout)
end
