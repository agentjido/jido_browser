defmodule Jido.Browser.Adapters.AgentBrowser do
  @moduledoc """
  Primary browser adapter backed by `agent-browser`.

  This adapter manages a supervised `agent-browser` daemon per browser session and
  communicates with it over the upstream local JSON socket/TCP protocol.
  """

  @behaviour Jido.Browser.Adapter

  alias Jido.Browser.AgentBrowser.PoolLease
  alias Jido.Browser.AgentBrowser.PoolManager
  alias Jido.Browser.AgentBrowser.Runtime
  alias Jido.Browser.AgentBrowser.SessionServer
  alias Jido.Browser.Error
  alias Jido.Browser.Session

  @default_timeout 30_000
  @default_checkout_timeout 5_000

  @spec start_pool(keyword()) :: {:ok, pid()} | {:error, term()}
  def start_pool(opts) do
    with :ok <- reject_pooled_session_name(opts),
         {:ok, name} <- fetch_pool_name(opts),
         {:ok, size} <- fetch_pool_size(opts),
         {:ok, session_opts} <- build_session_opts(opts) do
      startup_timeout =
        Keyword.get(
          opts,
          :startup_timeout,
          max(Keyword.get(session_opts, :timeout, @default_timeout), @default_timeout) * size
        )

      case PoolManager.start_pool(
             name: name,
             size: size,
             session_opts: session_opts,
             pool_runtime_module: Keyword.get(opts, :pool_runtime_module)
           ) do
        {:ok, pid} ->
          try do
            :ok = PoolManager.await_ready(pid, startup_timeout)
            {:ok, pid}
          catch
            :exit, reason ->
              _ = PoolManager.stop_pool(pid)
              {:error, Error.adapter_error("Failed to warm agent-browser pool", %{reason: reason})}
          end

        {:error, {:already_started, pid}} ->
          {:error, {:already_started, pid}}

        {:error, reason} ->
          {:error, Error.adapter_error("Failed to start agent-browser pool", %{reason: reason})}
      end
    end
  end

  @spec stop_pool(term()) :: :ok | {:error, term()}
  def stop_pool(pool), do: PoolManager.stop_pool(pool)

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
    case PoolLease.shutdown(pid) do
      :ok ->
        :ok

      {:error, reason} ->
        {:error, Error.adapter_error("Failed to end pooled session", %{reason: reason})}
    end
  end

  def end_session(%Session{runtime: %{pooled: true}}) do
    :ok
  end

  def end_session(%Session{runtime: %{manager: pid}}) when is_pid(pid) do
    SessionServer.shutdown(pid)
  end

  def end_session(%Session{id: session_id}) do
    case Runtime.lookup_session_server(session_id) do
      {:ok, pid} -> SessionServer.shutdown(pid)
      :error -> :ok
    end
  end

  @impl true
  def navigate(session, url, opts) do
    payload = %{"action" => "navigate", "url" => url}
    payload = maybe_put(payload, "waitUntil", opts[:wait_until])

    case run(session, payload, opts) do
      {:ok, session, data} ->
        updated_session = put_current_url(session, Map.get(data, "url", url))
        {:ok, updated_session, data}

      error ->
        error
    end
  end

  @impl true
  def click(session, selector, opts) do
    payload =
      %{"action" => "click", "selector" => selector}
      |> maybe_put("newTab", opts[:new_tab] || opts[:newTab])

    run(session, payload, opts)
  end

  @impl true
  def type(session, selector, text, opts) do
    payload =
      if Keyword.get(opts, :clear, false) do
        %{"action" => "fill", "selector" => selector, "value" => text}
      else
        %{"action" => "type", "selector" => selector, "text" => text}
      end

    run(session, payload, opts)
  end

  @impl true
  def screenshot(session, opts) do
    format = to_string(opts[:format] || :png)

    with_tmp_file("jido_browser_agent_browser", ".#{format}", fn path ->
      payload =
        %{
          "action" => "screenshot",
          "path" => path,
          "format" => format,
          "fullPage" => Keyword.get(opts, :full_page, false)
        }

      with {:ok, session, data} <- run(session, payload, opts),
           {:ok, bytes} <- File.read(data["path"] || path) do
        {:ok, session, %{bytes: bytes, mime: "image/#{format}", format: String.to_atom(format)}}
      else
        {:error, reason} ->
          {:error, Error.adapter_error("Screenshot failed", %{reason: reason})}
      end
    end)
  end

  @impl true
  def extract_content(session, opts) do
    selector = opts[:selector] || "body"
    format = opts[:format] || :markdown

    with {:ok, _session, html} <- fetch_html(session, selector, opts),
         {:ok, content} <- convert_content(session, html, selector, format, opts) do
      {:ok, session, %{content: content, format: format}}
    else
      {:error, reason} ->
        {:error, Error.adapter_error("Extract content failed", %{reason: reason})}
    end
  end

  @impl true
  def evaluate(session, script, opts) do
    run(session, %{"action" => "evaluate", "script" => script}, opts)
  end

  @impl true
  def command(session, action, opts) do
    payload = command_payload(action, opts)
    run(session, payload, opts)
  end

  defp command_payload(:back, _opts), do: %{"action" => "back"}
  defp command_payload(:forward, _opts), do: %{"action" => "forward"}
  defp command_payload(:reload, _opts), do: %{"action" => "reload"}
  defp command_payload(:get_url, _opts), do: %{"action" => "url"}
  defp command_payload(:get_title, _opts), do: %{"action" => "title"}
  defp command_payload(:hover, opts), do: %{"action" => "hover", "selector" => Keyword.fetch!(opts, :selector)}
  defp command_payload(:focus, opts), do: %{"action" => "focus", "selector" => Keyword.fetch!(opts, :selector)}

  defp command_payload(:scroll, opts) do
    %{"action" => "scroll"}
    |> maybe_put("selector", opts[:selector])
    |> maybe_put("direction", opts[:direction] && to_string(opts[:direction]))
    |> maybe_put("amount", opts[:amount])
    |> maybe_put("x", opts[:x])
    |> maybe_put("y", opts[:y])
  end

  defp command_payload(:select_option, opts) do
    %{"action" => "select", "selector" => Keyword.fetch!(opts, :selector)}
    |> maybe_put("values", opts[:values] || opts[:value] || opts[:label])
  end

  defp command_payload(:wait_for_selector, opts) do
    %{
      "action" => "wait",
      "selector" => Keyword.fetch!(opts, :selector),
      "state" => to_string(opts[:state] || :visible),
      "timeout" => opts[:timeout] || @default_timeout
    }
  end

  defp command_payload(:wait_for_navigation, opts) do
    timeout = opts[:timeout] || @default_timeout

    cond do
      url = opts[:url] ->
        %{"action" => "waitforurl", "url" => url, "timeout" => timeout}

      load_state = opts[:load_state] ->
        %{"action" => "waitforloadstate", "state" => load_state, "timeout" => timeout}

      true ->
        %{"action" => "waitforloadstate", "state" => "load", "timeout" => timeout}
    end
  end

  defp command_payload(:get_text, opts), do: %{"action" => "gettext", "selector" => Keyword.fetch!(opts, :selector)}

  defp command_payload(:get_attribute, opts) do
    %{
      "action" => "getattribute",
      "selector" => Keyword.fetch!(opts, :selector),
      "attribute" => Keyword.fetch!(opts, :attribute)
    }
  end

  defp command_payload(:is_visible, opts), do: %{"action" => "isvisible", "selector" => Keyword.fetch!(opts, :selector)}
  defp command_payload(:count, opts), do: %{"action" => "count", "selector" => Keyword.fetch!(opts, :selector)}
  defp command_payload(:content, _opts), do: %{"action" => "content"}

  defp command_payload(:snapshot, opts) do
    %{"action" => "snapshot"}
    |> maybe_put("selector", opts[:selector])
    |> maybe_put("interactive", opts[:interactive])
    |> maybe_put("compact", opts[:compact])
    |> maybe_put("depth", opts[:depth])
    |> maybe_put("cursor", opts[:cursor])
  end

  defp command_payload(:save_state, opts), do: %{"action" => "state_save", "path" => Keyword.fetch!(opts, :path)}
  defp command_payload(:load_state, opts), do: %{"action" => "state_load", "path" => Keyword.fetch!(opts, :path)}
  defp command_payload(:list_tabs, _opts), do: %{"action" => "tab_list"}
  defp command_payload(:new_tab, opts), do: maybe_put(%{"action" => "tab_new"}, "url", opts[:url])
  defp command_payload(:switch_tab, opts), do: %{"action" => "tab_switch", "index" => Keyword.fetch!(opts, :index)}
  defp command_payload(:close_tab, opts), do: maybe_put(%{"action" => "tab_close"}, "index", opts[:index])
  defp command_payload(:console, _opts), do: %{"action" => "console"}
  defp command_payload(:errors, _opts), do: %{"action" => "errors"}

  defp run(%Session{runtime: %{pooled: true, manager: pid}} = session, payload, opts) when is_pid(pid) do
    timeout = opts[:timeout] || @default_timeout

    case PoolLease.command(pid, payload, timeout) do
      {:ok, data} ->
        {:ok, session, data}

      {:error, reason} ->
        {:error, Error.adapter_error("agent-browser pooled command failed", %{reason: reason, payload: payload})}
    end
  end

  defp run(%Session{runtime: %{pooled: true}}, _payload, _opts) do
    {:error, Error.adapter_error("No pooled agent-browser lease available", %{})}
  end

  defp run(%Session{runtime: %{manager: pid}} = session, payload, opts) when is_pid(pid) do
    timeout = opts[:timeout] || @default_timeout

    case SessionServer.command(pid, payload, timeout) do
      {:ok, data} ->
        {:ok, session, data}

      {:error, reason} ->
        {:error, Error.adapter_error("agent-browser command failed", %{reason: reason, payload: payload})}
    end
  end

  defp run(%Session{id: session_id} = session, payload, opts) do
    case Runtime.lookup_session_server(session_id) do
      {:ok, pid} ->
        run(put_runtime_pid(session, pid), payload, opts)

      :error ->
        {:error, Error.adapter_error("No agent-browser session server available", %{session_id: session_id})}
    end
  end

  defp fetch_html(session, selector, opts) when selector in [nil, "", "body"] do
    case command(session, :content, opts) do
      {:ok, session, %{"html" => html}} -> {:ok, session, html}
      {:ok, _session, data} -> {:error, "Unexpected content response: #{inspect(data)}"}
      {:error, reason} -> {:error, reason}
    end
  end

  defp fetch_html(session, selector, opts) do
    script = """
    (() => {
      const el = document.querySelector(#{Jason.encode!(selector)});
      return el ? el.outerHTML : null;
    })()
    """

    case evaluate(session, script, opts) do
      {:ok, session, %{"result" => html}} when is_binary(html) -> {:ok, session, html}
      {:ok, _session, _data} -> {:error, "Selector #{selector} did not match any element"}
      {:error, reason} -> {:error, reason}
    end
  end

  defp convert_content(_session, html, _selector, :html, _opts), do: {:ok, html}

  defp convert_content(session, _html, selector, :text, opts) do
    selector = normalize_selector(selector)

    case command(session, :get_text, Keyword.merge(opts, selector: selector)) do
      {:ok, _session, %{"text" => text}} when is_binary(text) -> {:ok, text}
      {:ok, _session, data} -> {:error, "Unexpected text response: #{inspect(data)}"}
      {:error, reason} -> {:error, reason}
    end
  end

  defp convert_content(_session, html, _selector, :markdown, _opts) do
    {:ok, Html2Markdown.convert(html)}
  rescue
    error ->
      {:error, Exception.message(error)}
  end

  defp put_runtime_pid(%Session{runtime: runtime} = session, pid) when is_map(runtime) do
    %{session | runtime: Map.put(runtime, :manager, pid)}
  end

  defp put_runtime_pid(session, _pid), do: session

  defp put_current_url(%Session{connection: connection} = session, current_url) do
    %{session | connection: Map.put(connection || %{}, :current_url, current_url)}
  end

  defp normalize_selector(selector) when selector in [nil, ""], do: "body"
  defp normalize_selector(selector), do: selector

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, false), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp with_tmp_file(prefix, suffix, fun) do
    path = Path.join(System.tmp_dir!(), "#{prefix}_#{System.unique_integer([:positive])}#{suffix}")

    try do
      fun.(path)
    after
      File.rm(path)
    end
  end

  defp start_unpooled_session(opts) do
    with {:ok, session_opts} <- build_session_opts(opts) do
      session_id = opts[:session_id] || Uniq.UUID.uuid4()

      case Runtime.ensure_session_server(session_id, session_opts) do
        {:ok, pid, runtime} ->
          build_session(session_id, session_opts, runtime, pid)

        {:error, reason} ->
          {:error, Error.adapter_error("Failed to start agent-browser session", %{reason: reason})}
      end
    end
  end

  defp start_pooled_session(pool, opts) do
    with :ok <- reject_pooled_session_name(opts),
         {:ok, lease_pid, worker_state} <-
           PoolManager.checkout_session(
             pool,
             owner: self(),
             checkout_timeout: Keyword.get(opts, :checkout_timeout, @default_checkout_timeout)
           ) do
      Session.new(%{
        id: opts[:session_id] || Uniq.UUID.uuid4(),
        adapter: __MODULE__,
        connection: %{
          binary: worker_state.binary,
          session_id: worker_state.session_id,
          current_url: nil
        },
        runtime:
          worker_state.runtime
          |> Map.put(:manager, lease_pid)
          |> Map.put(:manager_module, PoolLease)
          |> Map.put(:pool, pool)
          |> Map.put(:pooled, true),
        capabilities: Runtime.capabilities(),
        opts:
          opts
          |> Keyword.put_new(:checkout_timeout, @default_checkout_timeout)
          |> Map.new()
      })
    else
      {:error, %Jido.Browser.Error.InvalidError{} = reason} ->
        {:error, reason}

      {:error, :pool_not_found} ->
        {:error, Error.adapter_error("No agent-browser pool available", %{pool: pool})}

      {:error, :pool_stopping} ->
        {:error, Error.adapter_error("Agent-browser pool is stopping", %{pool: pool})}

      {:error, :checkout_timeout} ->
        {:error, Error.adapter_error("Timed out waiting for a warm pooled session", %{pool: pool})}

      {:error, reason} ->
        {:error, Error.adapter_error("Failed to check out pooled agent-browser session", %{pool: pool, reason: reason})}
    end
  end

  defp build_session_opts(opts) do
    with {:ok, binary} <- Runtime.find_binary(),
         :ok <- Runtime.ensure_supported_version(binary) do
      headed = Keyword.get(opts, :headed, not Keyword.get(opts, :headless, true))
      timeout = Keyword.get(opts, :timeout, @default_timeout)

      {:ok,
       opts
       |> Keyword.put(:binary, binary)
       |> Keyword.put(:headed, headed)
       |> Keyword.put(:timeout, timeout)}
    end
  end

  defp build_session(session_id, session_opts, runtime, pid) do
    Session.new(%{
      id: session_id,
      adapter: __MODULE__,
      connection: %{
        binary: Keyword.fetch!(session_opts, :binary),
        session_id: session_id,
        current_url: nil
      },
      runtime: Map.put(runtime, :manager, pid),
      capabilities: Runtime.capabilities(),
      opts: Map.new(session_opts)
    })
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

  defp reject_pooled_session_name(opts) do
    if opts[:session_name] do
      {:error,
       Error.invalid_error("Pooled agent-browser sessions do not support session_name", %{
         session_name: opts[:session_name]
       })}
    else
      :ok
    end
  end
end
