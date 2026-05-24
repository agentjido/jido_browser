defmodule Jido.Browser.Adapters.Lightpanda do
  @moduledoc """
  Limited Lightpanda adapter backed by `light_cdp`.

  This adapter covers the base `Jido.Browser.Adapter` contract using
  Lightpanda's Chrome DevTools Protocol support. It is intended for lightweight
  DOM and JavaScript automation, not full browser parity with AgentBrowser.

  ## Optional dependencies

  Add the optional Lightpanda dependencies in the host application when using
  this adapter:

      {:light_cdp, "~> 0.2.1"}
      {:lightpanda_ex, "~> 0.1.0"}

  ## Configuration

      config :jido_browser,
        adapter: Jido.Browser.Adapters.Lightpanda,
        lightpanda: [
          binary_path: "/path/to/lightpanda",
          disable_telemetry: true
        ]

  Lightpanda telemetry is disabled by default by setting
  `LIGHTPANDA_DISABLE_TELEMETRY=true` before the browser process starts.
  """

  @compile {:no_warn_undefined, LightCDP}
  @compile {:no_warn_undefined, LightCDP.Page}

  @behaviour Jido.Browser.Adapter
  @behaviour Jido.Browser.PoolAdapter

  alias Jido.Browser.Adapters.Lightpanda.PoolRuntime
  alias Jido.Browser.Application, as: BrowserApplication
  alias Jido.Browser.Error
  alias Jido.Browser.Installer
  alias Jido.Browser.Session
  alias Jido.Browser.WarmPool.Lease
  alias Jido.Browser.WarmPool.Manager
  alias Jido.Browser.WarmPool.TreeSupervisor

  @default_timeout 30_000
  @default_checkout_timeout 5_000
  @default_server_timeout 30
  @supported_screenshot_formats [:png]
  @supported_extract_formats [:markdown, :html, :text]

  @impl true
  @spec start_pool(keyword()) :: {:ok, pid()} | {:error, term()}
  def start_pool(opts) do
    with {:ok, manager_opts, startup_timeout} <- build_pool_start_opts(opts) do
      case TreeSupervisor.start_pool(manager_opts) do
        {:ok, pid} ->
          await_pool_ready(pid, startup_timeout, "Failed to warm Lightpanda adapter pool")

        {:error, {:already_started, pid}} ->
          {:error, {:already_started, pid}}

        {:error, reason} ->
          {:error, Error.adapter_error("Failed to start Lightpanda adapter pool", %{reason: reason})}
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
          await_pool_ready(pid, startup_timeout, "Failed to warm supervised Lightpanda adapter pool")

        {:error, {:already_started, pid}} ->
          {:error, {:already_started, pid}}

        {:error, reason} ->
          {:error, Error.adapter_error("Failed to start supervised Lightpanda adapter pool", %{reason: reason})}
      end
    end
  end

  @impl true
  @spec stop_pool(term()) :: :ok | {:error, term()}
  def stop_pool(pool), do: TreeSupervisor.stop_pool(pool)

  @impl true
  @spec start_session(keyword()) :: {:ok, Session.t()} | {:error, Error.t()}
  def start_session(opts \\ []) do
    if pool = opts[:pool] do
      start_pooled_session(pool, opts)
    else
      start_unpooled_session(opts)
    end
  end

  @doc false
  def start_connection(opts \\ []) do
    light_cdp = light_cdp_module(opts)
    page_module = page_module(opts)

    with :ok <- ensure_optional_module(light_cdp, "light_cdp optional dependency"),
         :ok <- ensure_optional_module(page_module, "light_cdp optional dependency"),
         {:ok, binary} <- find_lightpanda_binary(opts),
         :ok <- maybe_disable_telemetry(opts),
         {:ok, cdp_session} <- call(light_cdp, :start, [start_opts(opts, binary)]) do
      start_page(light_cdp, page_module, cdp_session, binary)
    else
      {:error, %Error.AdapterError{} = error} ->
        {:error, error}

      {:error, reason} ->
        {:error, Error.adapter_error("Failed to start Lightpanda session", %{reason: reason, adapter: __MODULE__})}
    end
  end

  @doc false
  def stop_connection(%{cdp_session: cdp_session, light_cdp_module: light_cdp}) do
    case call(light_cdp, :stop, [cdp_session]) do
      :ok -> :ok
      {:ok, _} -> :ok
      {:error, reason} -> {:error, Error.adapter_error("Failed to stop Lightpanda session", %{reason: reason})}
      other -> {:error, Error.adapter_error("Failed to stop Lightpanda session", %{reason: other})}
    end
  end

  @impl true
  @spec end_session(Session.t()) :: :ok | {:error, Error.t()}
  def end_session(%Session{runtime: %{pooled: true, manager: pid}}) when is_pid(pid) do
    case Lease.shutdown(pid) do
      :ok -> :ok
      {:error, reason} -> {:error, Error.adapter_error("Failed to end pooled Lightpanda session", %{reason: reason})}
    end
  end

  def end_session(%Session{runtime: %{pooled: true}}), do: :ok

  def end_session(%Session{connection: %{cdp_session: cdp_session, light_cdp_module: light_cdp}}) do
    stop_connection(%{cdp_session: cdp_session, light_cdp_module: light_cdp})
  end

  def end_session(%Session{}), do: :ok

  @impl true
  @spec navigate(Session.t(), String.t(), keyword()) :: {:ok, Session.t(), map()} | {:error, Error.t()}
  def navigate(%Session{} = session, url, opts) do
    case page_call(session, :navigate, [page(session), url, timeout_opts(opts)]) do
      :ok ->
        updated_session = put_current_url(session, url)
        {:ok, updated_session, %{url: url}}

      {:error, reason} ->
        {:error, Error.navigation_error(url, reason)}
    end
  end

  @impl true
  @spec click(Session.t(), String.t(), keyword()) :: {:ok, Session.t(), map()} | {:error, Error.t()}
  def click(%Session{} = session, selector, opts) do
    case page_call(session, :click, [page(session), selector, timeout_opts(opts)]) do
      :ok -> {:ok, session, %{selector: selector}}
      {:error, reason} -> {:error, Error.element_error("click", selector, reason)}
    end
  end

  @impl true
  @spec type(Session.t(), String.t(), String.t(), keyword()) :: {:ok, Session.t(), map()} | {:error, Error.t()}
  def type(%Session{} = session, selector, text, opts) do
    case page_call(session, :fill, [page(session), selector, text, timeout_opts(opts)]) do
      :ok -> {:ok, session, %{selector: selector}}
      {:error, reason} -> {:error, Error.element_error("type", selector, reason)}
    end
  end

  @impl true
  @spec screenshot(Session.t(), keyword()) :: {:ok, Session.t(), map()} | {:error, Error.t()}
  def screenshot(%Session{} = session, opts) do
    format = opts[:format] || :png

    with :ok <- validate_screenshot_format(format),
         {:ok, bytes} <- page_call(session, :screenshot, [page(session), timeout_opts(opts)]) do
      {:ok, session, %{bytes: bytes, mime: "image/png", format: :png}}
    else
      {:error, %Error.AdapterError{} = error} ->
        {:error, error}

      {:error, reason} ->
        {:error, Error.adapter_error("Screenshot failed", %{reason: reason})}
    end
  end

  @impl true
  @spec extract_content(Session.t(), keyword()) :: {:ok, Session.t(), map()} | {:error, Error.t()}
  def extract_content(%Session{} = session, opts) do
    format = opts[:format] || :markdown
    selector = opts[:selector] || "body"

    with :ok <- validate_extract_format(format),
         {:ok, html} <- page_call(session, :content, [page(session)]),
         {:ok, selected_html} <- select_html(html, selector),
         {:ok, content} <- format_html(selected_html, format) do
      {:ok, session, %{content: content, format: format}}
    else
      {:error, %Error.AdapterError{} = error} ->
        {:error, error}

      {:error, reason} ->
        {:error, Error.adapter_error("Extract content failed", %{reason: reason})}
    end
  end

  @impl true
  @spec evaluate(Session.t(), String.t(), keyword()) :: {:ok, Session.t(), map()} | {:error, Error.t()}
  def evaluate(%Session{} = session, script, opts) do
    case page_call(session, :evaluate, [page(session), script, timeout_opts(opts)]) do
      {:ok, result} -> {:ok, session, %{result: result}}
      {:error, reason} -> {:error, Error.adapter_error("Evaluate failed", %{reason: reason})}
    end
  end

  defp start_unpooled_session(opts) do
    with {:ok, connection} <- start_connection(opts) do
      Session.new(%{
        adapter: __MODULE__,
        connection: connection,
        capabilities: capabilities(),
        opts: Map.new(opts)
      })
    end
  end

  defp start_pooled_session(pool, opts) do
    case checkout_pooled_session(pool, opts) do
      {:ok, lease_pid, worker_state} ->
        build_pooled_session(pool, opts, lease_pid, worker_state)

      {:error, :pool_not_found} ->
        {:error, Error.adapter_error("No Lightpanda adapter pool available", %{pool: pool})}

      {:error, :pool_stopping} ->
        {:error, Error.adapter_error("Lightpanda adapter pool is stopping", %{pool: pool})}

      {:error, :checkout_timeout} ->
        {:error, Error.adapter_error("Timed out waiting for a warm pooled session", %{pool: pool})}

      {:error, reason} ->
        {:error,
         Error.adapter_error("Failed to check out pooled Lightpanda adapter session", %{pool: pool, reason: reason})}
    end
  end

  defp checkout_pooled_session(pool, opts) do
    Manager.checkout_session(
      pool,
      owner: self(),
      checkout_timeout: Keyword.get(opts, :checkout_timeout, @default_checkout_timeout)
    )
  end

  defp build_pooled_session(pool, opts, lease_pid, worker_state) do
    Session.new(%{
      id: opts[:session_id] || Uniq.UUID.uuid4(),
      adapter: __MODULE__,
      connection:
        worker_state
        |> Map.take([:binary, :cdp_session, :page, :light_cdp_module, :page_module])
        |> Map.put(:current_url, nil),
      runtime:
        worker_state.runtime
        |> Map.put(:manager, lease_pid)
        |> Map.put(:manager_module, Lease)
        |> Map.put(:pool, pool)
        |> Map.put(:pooled, true),
      capabilities: capabilities(),
      opts:
        opts
        |> Keyword.put_new(:checkout_timeout, @default_checkout_timeout)
        |> Map.new()
    })
  end

  defp start_page(light_cdp, page_module, cdp_session, binary) do
    case call(light_cdp, :new_page, [cdp_session]) do
      {:ok, page} ->
        {:ok,
         %{
           binary: binary,
           cdp_session: cdp_session,
           page: page,
           current_url: nil,
           light_cdp_module: light_cdp,
           page_module: page_module
         }}

      {:error, reason} ->
        _ = call(light_cdp, :stop, [cdp_session])
        {:error, Error.adapter_error("Failed to create Lightpanda page", %{reason: reason, adapter: __MODULE__})}
    end
  end

  defp build_pool_start_opts(opts) do
    with {:ok, name} <- fetch_pool_name(opts),
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
    with {:ok, binary} <- find_lightpanda_binary(opts) do
      {:ok,
       opts |> Keyword.put(:binary, binary) |> Keyword.put(:pooled, true) |> Keyword.put_new(:timeout, @default_timeout)}
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

  defp capabilities do
    %{
      limited: true,
      javascript: true,
      screenshots: true,
      native_snapshot: false,
      tabs: false,
      state: false,
      pools: true
    }
  end

  defp start_opts(opts, binary) do
    port = Keyword.get(opts, :port) || configured_unpooled_port(opts) || free_port()

    [
      binary: binary,
      host: Keyword.get(opts, :host, config(:host, "127.0.0.1")),
      port: port,
      timeout: Keyword.get(opts, :server_timeout, config(:server_timeout, @default_server_timeout))
    ]
  end

  defp configured_unpooled_port(opts) do
    if opts[:pooled], do: nil, else: config(:port, nil)
  end

  defp maybe_disable_telemetry(opts) do
    if Keyword.get(opts, :disable_telemetry, config(:disable_telemetry, true)) do
      System.put_env("LIGHTPANDA_DISABLE_TELEMETRY", "true")
    end

    :ok
  end

  defp find_lightpanda_binary(opts) do
    case explicit_binary(opts) do
      path when is_binary(path) and path != "" ->
        validate_binary_path(path)

      _ ->
        case Installer.bin_path(:lightpanda) do
          path when is_binary(path) ->
            {:ok, path}

          nil ->
            {:error, "Lightpanda binary not found. Install with: mix jido_browser.install lightpanda"}
        end
    end
  end

  defp explicit_binary(opts) do
    opts[:binary] || opts[:binary_path] || config(:binary_path, nil)
  end

  defp validate_binary_path(path) do
    if File.exists?(path) do
      {:ok, path}
    else
      {:error, "Lightpanda binary not found at #{path}"}
    end
  end

  defp validate_screenshot_format(:png), do: :ok

  defp validate_screenshot_format(format) do
    {:error,
     Error.adapter_error("Lightpanda adapter only supports PNG screenshots", %{
       requested_format: format,
       supported_formats: @supported_screenshot_formats
     })}
  end

  defp validate_extract_format(format) when format in @supported_extract_formats, do: :ok

  defp validate_extract_format(format) do
    {:error,
     Error.adapter_error("Unsupported Lightpanda extract format", %{
       requested_format: format,
       supported_formats: @supported_extract_formats
     })}
  end

  defp select_html(html, selector) when selector in [nil, ""], do: {:ok, html}

  defp select_html(html, selector) do
    with {:ok, document} <- parse_document(html) do
      nodes = Floki.find(document, selector)

      if nodes == [] do
        {:error, Error.adapter_error("Selector did not match Lightpanda page content", %{selector: selector})}
      else
        {:ok, Floki.raw_html(nodes)}
      end
    end
  end

  defp parse_document(html) do
    case Floki.parse_document(html) do
      {:ok, document} -> {:ok, document}
      {:error, reason} -> {:error, Error.adapter_error("Failed to parse Lightpanda HTML", %{reason: reason})}
    end
  end

  defp format_html(html, :html), do: {:ok, html}

  defp format_html(html, :text) do
    case Floki.parse_fragment(html) do
      {:ok, fragment} -> {:ok, fragment |> Floki.text(sep: "\n") |> String.trim()}
      {:error, reason} -> {:error, Error.adapter_error("Failed to parse Lightpanda HTML fragment", %{reason: reason})}
    end
  end

  defp format_html(html, :markdown) do
    {:ok, html |> Html2Markdown.convert() |> String.trim()}
  rescue
    error ->
      {:error, Error.adapter_error("Failed to convert Lightpanda HTML to markdown", %{reason: error})}
  end

  defp page_call(%Session{} = session, function, args) do
    call(session_page_module(session), function, args)
  end

  defp call(module, function, args) do
    apply(module, function, args)
  rescue
    error -> {:error, error}
  catch
    kind, reason -> {:error, {kind, reason}}
  end

  defp ensure_optional_module(module, dependency) do
    if Code.ensure_loaded?(module) do
      :ok
    else
      {:error, Error.adapter_error("Lightpanda adapter requires #{dependency}", %{module: module, adapter: __MODULE__})}
    end
  end

  defp put_current_url(%Session{connection: connection} = session, url) do
    %{session | connection: Map.put(connection, :current_url, url)}
  end

  defp timeout_opts(opts), do: [timeout: opts[:timeout] || @default_timeout]
  defp page(%Session{connection: %{page: page}}), do: page
  defp session_page_module(%Session{connection: %{page_module: page_module}}), do: page_module
  defp light_cdp_module(opts), do: Keyword.get(opts, :light_cdp_module, config(:light_cdp_module, LightCDP))
  defp page_module(opts), do: Keyword.get(opts, :page_module, config(:page_module, LightCDP.Page))

  defp config(key, default) do
    :jido_browser
    |> Application.get_env(:lightpanda, [])
    |> Keyword.get(key, default)
  end

  defp free_port do
    {:ok, socket} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, port} = :inet.port(socket)
    :ok = :gen_tcp.close(socket)
    port
  end
end
