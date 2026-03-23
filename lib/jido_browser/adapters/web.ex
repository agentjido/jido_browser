defmodule Jido.Browser.Adapters.Web do
  @moduledoc """
  Adapter using chrismccord/web CLI.

  This adapter uses the `web` command-line tool which provides:
  - Firefox-based automation via Selenium
  - Built-in HTML to Markdown conversion
  - Phoenix LiveView-aware navigation
  - Session persistence with profiles

  `web_fetch/2` remains the simple HTTP-first retrieval path in `Jido.Browser`.
  This adapter is for browser-backed sessions and optionally warm pooled
  sessions when you need browser semantics with lower cold-start overhead.
  """

  @behaviour Jido.Browser.Adapter
  @behaviour Jido.Browser.PoolAdapter

  alias Jido.Browser.Adapters.Web.CLI
  alias Jido.Browser.Adapters.Web.PoolRuntime
  alias Jido.Browser.Application, as: BrowserApplication
  alias Jido.Browser.Error
  alias Jido.Browser.Session
  alias Jido.Browser.WarmPool.Lease
  alias Jido.Browser.WarmPool.Manager
  alias Jido.Browser.WarmPool.TreeSupervisor

  @default_timeout 30_000
  @default_checkout_timeout 5_000

  @impl true
  @spec start_pool(keyword()) :: {:ok, pid()} | {:error, term()}
  def start_pool(opts) do
    with {:ok, manager_opts, startup_timeout} <- build_pool_start_opts(opts) do
      case TreeSupervisor.start_pool(manager_opts) do
        {:ok, pid} ->
          await_pool_ready(pid, startup_timeout, "Failed to warm web adapter pool")

        {:error, {:already_started, pid}} ->
          {:error, {:already_started, pid}}

        {:error, reason} ->
          {:error, Error.adapter_error("Failed to start web adapter pool", %{reason: reason})}
      end
    end
  end

  @impl true
  @spec start_supervised_pool(keyword()) :: GenServer.on_start()
  def start_supervised_pool(opts) do
    with :ok <- BrowserApplication.ensure_started(),
         {:ok, manager_opts, startup_timeout} <- build_pool_start_opts(opts) do
      case TreeSupervisor.start_link(manager_opts) do
        {:ok, pid} ->
          await_pool_ready(pid, startup_timeout, "Failed to warm supervised web adapter pool")

        {:error, {:already_started, pid}} ->
          {:error, {:already_started, pid}}

        {:error, reason} ->
          {:error, Error.adapter_error("Failed to start supervised web adapter pool", %{reason: reason})}
      end
    end
  end

  @impl true
  @spec stop_pool(term()) :: :ok | {:error, term()}
  def stop_pool(pool), do: TreeSupervisor.stop_pool(pool)

  @impl true
  def start_session(opts \\ []) do
    if pool = opts[:pool] do
      start_pooled_session(pool, opts)
    else
      start_unpooled_session(opts)
    end
  end

  @impl true
  def end_session(%Session{runtime: %{pooled: true, manager: pid}}) when is_pid(pid) do
    case Lease.shutdown(pid) do
      :ok ->
        :ok

      {:error, reason} ->
        {:error, Error.adapter_error("Failed to end pooled web adapter session", %{reason: reason})}
    end
  end

  def end_session(%Session{runtime: %{pooled: true}}), do: :ok

  def end_session(%Session{}) do
    # The web CLI is stateless between invocations. Unpooled sessions are just
    # profile metadata, and pooled sessions recycle through the warm pool lease.
    :ok
  end

  @impl true
  def navigate(session, url, opts) do
    case run(session, %{"action" => "navigate", "url" => url}, opts) do
      {:ok, session, data} ->
        current_url = data["url"] || url
        {:ok, put_current_url(session, current_url), %{url: current_url, content: data["content"]}}

      {:error, reason} ->
        {:error, Error.navigation_error(url, reason)}
    end
  end

  @impl true
  def click(session, selector, opts) do
    payload =
      %{"action" => "click", "selector" => selector}
      |> maybe_put("text", opts[:text])

    case run(session, payload, opts) do
      {:ok, session, data} ->
        {:ok, session, %{selector: selector, content: data["content"]}}

      {:error, reason} ->
        {:error, Error.element_error("click", selector, reason)}
    end
  end

  @impl true
  def type(session, selector, text, opts) do
    payload = %{"action" => "type", "selector" => selector, "text" => text}

    case run(session, payload, opts) do
      {:ok, session, data} ->
        {:ok, session, %{selector: selector, content: data["content"]}}

      {:error, reason} ->
        {:error, Error.element_error("type", selector, reason)}
    end
  end

  @impl true
  def screenshot(%Session{} = session, opts) do
    format = opts[:format] || :png

    with :ok <- validate_screenshot_format(format),
         {:ok, session, data} <-
           run(
             session,
             %{
               "action" => "screenshot",
               "format" => "png",
               "full_page" => Keyword.get(opts, :full_page, false)
             },
             opts
           ) do
      {:ok, session, %{bytes: data["bytes"], mime: data["mime"], format: :png}}
    else
      {:error, _reason} = error ->
        error
    end
  end

  @impl true
  def extract_content(%Session{} = session, opts) do
    format = opts[:format] || :markdown

    case run(session, %{"action" => "extract_content", "selector" => opts[:selector], "format" => format}, opts) do
      {:ok, session, data} ->
        {:ok, session, %{content: data["content"], format: format}}

      {:error, reason} ->
        {:error, Error.adapter_error("Extract content failed", %{reason: reason})}
    end
  end

  @impl true
  def evaluate(%Session{} = session, script, opts) do
    case run(session, %{"action" => "evaluate", "script" => script}, opts) do
      {:ok, session, data} ->
        {:ok, session, %{result: data["result"]}}

      {:error, reason} ->
        {:error, Error.adapter_error("Evaluate failed", %{reason: reason})}
    end
  end

  defp validate_screenshot_format(:png), do: :ok

  defp validate_screenshot_format(:jpeg) do
    {:error,
     Error.adapter_error("Web adapter only supports PNG screenshots", %{
       requested_format: :jpeg,
       supported_formats: [:png]
     })}
  end

  defp validate_screenshot_format(other) do
    {:error,
     Error.adapter_error("Unsupported screenshot format", %{
       requested_format: other,
       supported_formats: [:png]
     })}
  end

  defp run(%Session{runtime: %{pooled: true, manager: pid}, connection: connection} = session, payload, opts)
       when is_pid(pid) do
    timeout = opts[:timeout] || @default_timeout
    payload = maybe_put(payload, "current_url", connection && connection.current_url)

    case Lease.command(pid, payload, timeout) do
      {:ok, data} ->
        {:ok, session, data}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp run(%Session{runtime: %{pooled: true}}, _payload, _opts) do
    {:error, :lease_unavailable}
  end

  defp run(%Session{connection: connection} = session, payload, opts) do
    timeout = opts[:timeout] || @default_timeout
    payload = maybe_put(payload, "current_url", connection && connection.current_url)
    binary = connection && connection[:binary]

    case CLI.execute(connection.profile, payload, [timeout: timeout] |> maybe_put_opt(:binary, binary)) do
      {:ok, data} ->
        {:ok, session, data}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp start_unpooled_session(opts) do
    with {:ok, binary} <- CLI.find_binary(opts) do
      profile = opts[:profile] || config(:profile, "default")
      session_opts = Keyword.put(opts, :binary, binary)

      Session.new(%{
        adapter: __MODULE__,
        connection: %{profile: profile, current_url: nil, binary: binary},
        opts: Map.new(session_opts)
      })
    end
  end

  defp start_pooled_session(pool, opts) do
    with :ok <- reject_pooled_state_opts(opts),
         {:ok, lease_pid, worker_state} <-
           Manager.checkout_session(
             pool,
             owner: self(),
             checkout_timeout: Keyword.get(opts, :checkout_timeout, @default_checkout_timeout)
           ) do
      Session.new(%{
        id: opts[:session_id] || Uniq.UUID.uuid4(),
        adapter: __MODULE__,
        connection: %{profile: worker_state.profile, current_url: nil, binary: worker_state.binary},
        runtime:
          worker_state.runtime
          |> Map.put(:manager, lease_pid)
          |> Map.put(:manager_module, Lease)
          |> Map.put(:pool, pool)
          |> Map.put(:pooled, true),
        opts:
          opts
          |> Keyword.put_new(:checkout_timeout, @default_checkout_timeout)
          |> Map.new()
      })
    else
      {:error, %Jido.Browser.Error.InvalidError{} = reason} ->
        {:error, reason}

      {:error, :pool_not_found} ->
        {:error, Error.adapter_error("No web adapter pool available", %{pool: pool})}

      {:error, :pool_stopping} ->
        {:error, Error.adapter_error("Web adapter pool is stopping", %{pool: pool})}

      {:error, :checkout_timeout} ->
        {:error, Error.adapter_error("Timed out waiting for a warm pooled session", %{pool: pool})}

      {:error, reason} ->
        {:error, Error.adapter_error("Failed to check out pooled web adapter session", %{pool: pool, reason: reason})}
    end
  end

  defp build_pool_start_opts(opts) do
    with :ok <- reject_pooled_state_opts(opts),
         {:ok, name} <- fetch_pool_name(opts),
         {:ok, size} <- fetch_pool_size(opts),
         {:ok, worker_opts} <- build_worker_opts(opts) do
      manager_opts = [
        name: name,
        size: size,
        adapter: __MODULE__,
        worker_opts: Keyword.put(worker_opts, :pool_name, name),
        pool_runtime_module: Keyword.get(opts, :pool_runtime_module, PoolRuntime)
      ]

      startup_timeout =
        Keyword.get(
          opts,
          :startup_timeout,
          max(Keyword.get(worker_opts, :timeout, @default_timeout), @default_timeout) * size
        )

      {:ok, manager_opts, startup_timeout}
    end
  end

  defp build_worker_opts(opts) do
    with {:ok, binary} <- CLI.find_binary(opts) do
      timeout = Keyword.get(opts, :timeout, @default_timeout)
      {:ok, opts |> Keyword.put(:binary, binary) |> Keyword.put(:timeout, timeout)}
    end
  end

  defp await_pool_ready(pid, startup_timeout, message) do
    :ok = TreeSupervisor.await_ready(pid, startup_timeout)
    {:ok, pid}
  catch
    :exit, reason ->
      Process.unlink(pid)
      _ = GenServer.stop(pid, :shutdown, 10_000)
      {:error, Error.adapter_error(message, %{reason: reason})}
  end

  defp fetch_pool_name(opts) do
    case opts[:name] do
      nil -> {:error, Error.invalid_error("Pool name is required", %{})}
      name -> {:ok, name}
    end
  end

  defp fetch_pool_size(opts) do
    case opts[:size] do
      size when is_integer(size) and size > 0 -> {:ok, size}
      size -> {:error, Error.invalid_error("Pool size must be a positive integer", %{size: size})}
    end
  end

  defp reject_pooled_state_opts(opts) do
    cond do
      opts[:profile] ->
        {:error, Error.invalid_error("Pooled web adapter sessions do not support profile", %{profile: opts[:profile]})}

      opts[:session_name] ->
        {:error,
         Error.invalid_error("Pooled web adapter sessions do not support session_name", %{
           session_name: opts[:session_name]
         })}

      true ->
        :ok
    end
  end

  defp put_current_url(%Session{connection: connection} = session, current_url) do
    %{session | connection: Map.put(connection || %{}, :current_url, current_url)}
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
  defp maybe_put_opt(opts, _key, nil), do: opts
  defp maybe_put_opt(opts, key, value), do: Keyword.put(opts, key, value)

  defp config(key, default) do
    :jido_browser
    |> Application.get_env(:web, [])
    |> Keyword.get(key, default)
  end
end
