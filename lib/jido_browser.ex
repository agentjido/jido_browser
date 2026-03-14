defmodule Jido.Browser do
  @moduledoc """
  Browser automation for Jido AI agents.

  `Jido.Browser` provides a flat browser API backed by pluggable adapters.
  In 2.0, the default adapter is `Jido.Browser.Adapters.AgentBrowser`.
  """

  alias Jido.Browser.Error
  alias Jido.Browser.Session

  @default_adapter Jido.Browser.Adapters.AgentBrowser
  @default_timeout 30_000
  @supported_screenshot_formats [:png]
  @supported_extract_formats [:markdown, :html, :text]

  @doc "Starts a browser session using the configured adapter or an explicit adapter override."
  @spec start_session(keyword()) :: {:ok, Session.t()} | {:error, term()}
  def start_session(opts \\ []) do
    adapter = opts[:adapter] || configured_adapter()

    case adapter.start_session(opts) do
      %Session{} = session -> {:ok, session}
      error -> error
    end
  end

  @doc "Ends an active browser session."
  @spec end_session(Session.t()) :: :ok | {:error, term()}
  def end_session(%Session{} = session), do: session.adapter.end_session(session)

  @doc "Navigates the current session to a URL."
  @spec navigate(Session.t(), String.t(), keyword()) ::
          {:ok, Session.t(), map()} | {:error, term()}
  def navigate(session, url, opts \\ [])

  def navigate(%Session{}, url, _opts) when url in [nil, ""] do
    {:error, Error.invalid_error("URL cannot be nil or empty", %{url: url})}
  end

  def navigate(%Session{} = session, url, opts) do
    session.adapter.navigate(session, url, normalize_timeout(opts))
  end

  @doc "Clicks an element identified by a selector or agent-browser ref."
  @spec click(Session.t(), String.t(), keyword()) ::
          {:ok, Session.t(), map()} | {:error, term()}
  def click(session, selector, opts \\ [])

  def click(%Session{}, selector, _opts) when selector in [nil, ""] do
    {:error, Error.invalid_error("Selector cannot be nil or empty", %{selector: selector})}
  end

  def click(%Session{} = session, selector, opts) do
    session.adapter.click(session, selector, normalize_timeout(opts))
  end

  @doc "Types text into an element identified by a selector or agent-browser ref."
  @spec type(Session.t(), String.t(), String.t(), keyword()) ::
          {:ok, Session.t(), map()} | {:error, term()}
  def type(session, selector, text, opts \\ [])

  def type(%Session{}, selector, _text, _opts) when selector in [nil, ""] do
    {:error, Error.invalid_error("Selector cannot be nil or empty", %{selector: selector})}
  end

  def type(%Session{} = session, selector, text, opts) do
    session.adapter.type(session, selector, text, normalize_timeout(opts))
  end

  @doc "Captures a screenshot of the current page."
  @spec screenshot(Session.t(), keyword()) :: {:ok, Session.t(), map()} | {:error, term()}
  def screenshot(%Session{} = session, opts \\ []) do
    format = opts[:format] || :png

    if format in @supported_screenshot_formats do
      session.adapter.screenshot(session, normalize_timeout(opts))
    else
      {:error,
       Error.invalid_error("Unsupported screenshot format: #{inspect(format)}", %{
         format: format,
         supported: @supported_screenshot_formats
       })}
    end
  end

  @doc "Extracts page content as markdown, HTML, or text."
  @spec extract_content(Session.t(), keyword()) ::
          {:ok, Session.t(), map()} | {:error, term()}
  def extract_content(%Session{} = session, opts \\ []) do
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

  @doc "Evaluates JavaScript in the browser when the adapter supports it."
  @spec evaluate(Session.t(), String.t(), keyword()) ::
          {:ok, Session.t(), map()} | {:error, term()}
  def evaluate(session, script, opts \\ [])

  def evaluate(%Session{}, script, _opts) when script in [nil, ""] do
    {:error, Error.invalid_error("Script cannot be nil or empty", %{script: script})}
  end

  def evaluate(%Session{adapter: adapter} = session, script, opts) do
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

  @doc "Navigates back in browser history."
  @spec back(Session.t(), keyword()) :: {:ok, Session.t(), map()} | {:error, term()}
  def back(%Session{} = session, opts \\ []) do
    command_or_fallback(session, :back, opts, fn ->
      evaluate(session, "window.history.back()", opts)
    end)
  end

  @doc "Navigates forward in browser history."
  @spec forward(Session.t(), keyword()) :: {:ok, Session.t(), map()} | {:error, term()}
  def forward(%Session{} = session, opts \\ []) do
    command_or_fallback(session, :forward, opts, fn ->
      evaluate(session, "window.history.forward()", opts)
    end)
  end

  @doc "Reloads the current page."
  @spec reload(Session.t(), keyword()) :: {:ok, Session.t(), map()} | {:error, term()}
  def reload(%Session{} = session, opts \\ []) do
    command_or_fallback(session, :reload, opts, fn ->
      evaluate(session, "window.location.reload()", opts)
    end)
  end

  @doc "Returns the current page URL."
  @spec get_url(Session.t(), keyword()) :: {:ok, Session.t(), map()} | {:error, term()}
  def get_url(%Session{} = session, opts \\ []) do
    command_or_fallback(session, :get_url, opts, fn ->
      with {:ok, session, %{result: result}} <- evaluate(session, "window.location.href", opts) do
        {:ok, session, %{url: result}}
      end
    end)
  end

  @doc "Returns the current page title."
  @spec get_title(Session.t(), keyword()) :: {:ok, Session.t(), map()} | {:error, term()}
  def get_title(%Session{} = session, opts \\ []) do
    command_or_fallback(session, :get_title, opts, fn ->
      with {:ok, session, %{result: result}} <- evaluate(session, "document.title", opts) do
        {:ok, session, %{title: result}}
      end
    end)
  end

  @doc "Moves the pointer over an element."
  @spec hover(Session.t(), String.t(), keyword()) :: {:ok, Session.t(), map()} | {:error, term()}
  def hover(%Session{} = session, selector, opts \\ []) do
    command_or_fallback(session, :hover, Keyword.put(opts, :selector, selector), fn ->
      script = """
      (() => {
        const el = document.querySelector(#{Jason.encode!(selector)});
        if (!el) return {hovered: false, error: "Element not found"};
        el.dispatchEvent(new MouseEvent("mouseenter", {bubbles: true, cancelable: true}));
        el.dispatchEvent(new MouseEvent("mouseover", {bubbles: true, cancelable: true}));
        return {hovered: true, selector: #{Jason.encode!(selector)}};
      })()
      """

      evaluate(session, script, opts)
    end)
  end

  @doc "Focuses an element."
  @spec focus(Session.t(), String.t(), keyword()) :: {:ok, Session.t(), map()} | {:error, term()}
  def focus(%Session{} = session, selector, opts \\ []) do
    command_or_fallback(session, :focus, Keyword.put(opts, :selector, selector), fn ->
      script = """
      (() => {
        const el = document.querySelector(#{Jason.encode!(selector)});
        if (!el) return {focused: false, error: "Element not found"};
        el.focus();
        return {focused: true, selector: #{Jason.encode!(selector)}};
      })()
      """

      evaluate(session, script, opts)
    end)
  end

  @doc "Scrolls the page, by coordinates, direction, or to a specific element."
  @spec scroll(Session.t(), keyword()) :: {:ok, Session.t(), map()} | {:error, term()}
  def scroll(%Session{} = session, opts \\ []) do
    command_or_fallback(session, :scroll, opts, fn ->
      evaluate(session, build_scroll_script(opts), opts)
    end)
  end

  @doc "Selects an option in a form control."
  @spec select_option(Session.t(), String.t(), keyword()) ::
          {:ok, Session.t(), map()} | {:error, term()}
  def select_option(%Session{} = session, selector, opts \\ []) do
    native_supported? = opts[:value] || opts[:values] || opts[:label]

    if native_supported? do
      command_or_fallback(session, :select_option, Keyword.put(opts, :selector, selector), fn ->
        fallback_select_option(session, selector, opts)
      end)
    else
      fallback_select_option(session, selector, opts)
    end
  end

  @doc "Waits for a selector to reach a requested state."
  @spec wait_for_selector(Session.t(), String.t(), keyword()) ::
          {:ok, Session.t(), map()} | {:error, term()}
  def wait_for_selector(%Session{} = session, selector, opts \\ []) do
    command_or_fallback(session, :wait_for_selector, Keyword.put(opts, :selector, selector), fn ->
      state = opts[:state] || :visible
      timeout = opts[:timeout] || @default_timeout
      state_str = to_string(state)

      script = """
      (function waitForSelector(sel, state, timeout) {
        const start = Date.now();
        return new Promise((resolve, reject) => {
          function check() {
            const el = document.querySelector(sel);
            const elapsed = Date.now() - start;
            if (elapsed > timeout) {
              reject(new Error("Timeout waiting for " + sel));
              return;
            }
            let found = false;
            if (state === "attached") found = !!el;
            else if (state === "detached") found = !el;
            else if (state === "visible") found = el && el.offsetParent !== null;
            else if (state === "hidden") found = !el || el.offsetParent === null;
            if (found) resolve({found: true, elapsed: elapsed});
            else setTimeout(check, 100);
          }
          check();
        });
      })(#{Jason.encode!(selector)}, #{Jason.encode!(state_str)}, #{timeout})
      """

      evaluate(session, script, opts)
    end)
  end

  @doc "Waits for a navigation or URL change to complete."
  @spec wait_for_navigation(Session.t(), keyword()) ::
          {:ok, Session.t(), map()} | {:error, term()}
  def wait_for_navigation(%Session{} = session, opts \\ []) do
    command_or_fallback(session, :wait_for_navigation, opts, fn ->
      timeout = opts[:timeout] || @default_timeout

      script =
        if url_pattern = opts[:url] do
          """
          (function waitForNav(urlPattern, timeout) {
            const start = Date.now();
            const startUrl = window.location.href;
            return new Promise((resolve, reject) => {
              function check() {
                const elapsed = Date.now() - start;
                if (elapsed > timeout) {
                  reject(new Error("Navigation timeout"));
                  return;
                }
                const currentUrl = window.location.href;
                if (currentUrl !== startUrl && currentUrl.includes(urlPattern)) {
                  resolve({url: currentUrl, elapsed: elapsed});
                } else {
                  setTimeout(check, 100);
                }
              }
              check();
            });
          })(#{Jason.encode!(url_pattern)}, #{timeout})
          """
        else
          """
          (function waitForNav(timeout) {
            const start = Date.now();
            const startUrl = window.location.href;
            return new Promise((resolve, reject) => {
              function check() {
                const elapsed = Date.now() - start;
                if (elapsed > timeout) {
                  reject(new Error("Navigation timeout"));
                  return;
                }
                const currentUrl = window.location.href;
                if (currentUrl !== startUrl) {
                  resolve({url: currentUrl, elapsed: elapsed});
                } else {
                  setTimeout(check, 100);
                }
              }
              check();
            });
          })(#{timeout})
          """
        end

      evaluate(session, script, opts)
    end)
  end

  @doc "Queries a selector and returns a stable element summary."
  @spec query(Session.t(), String.t(), keyword()) :: {:ok, Session.t(), map()} | {:error, term()}
  def query(%Session{} = session, selector, opts \\ []) do
    limit = opts[:limit] || 10

    with {:ok, session, elements} <- query_elements(session, selector, limit, opts) do
      case query_count(session, selector, opts) do
        {:ok, session, count} ->
          {:ok, session, %{count: count, elements: elements}}

        {:error, _reason} ->
          {:ok, session, %{count: length(elements), elements: elements}}
      end
    end
  end

  @doc "Reads text content from one or more matching elements."
  @spec get_text(Session.t(), String.t(), keyword()) :: {:ok, Session.t(), map()} | {:error, term()}
  def get_text(%Session{} = session, selector, opts \\ []) do
    if opts[:all] do
      get_all_text(session, selector, opts)
    else
      command_or_fallback(session, :get_text, Keyword.put(opts, :selector, selector), fn ->
        get_single_text(session, selector, opts)
      end)
    end
  end

  @doc "Reads an attribute value from an element."
  @spec get_attribute(Session.t(), String.t(), String.t(), keyword()) ::
          {:ok, Session.t(), map()} | {:error, term()}
  def get_attribute(%Session{} = session, selector, attribute, opts \\ []) do
    command_or_fallback(session, :get_attribute, Keyword.merge(opts, selector: selector, attribute: attribute), fn ->
      script = """
      (() => {
        const el = document.querySelector(#{Jason.encode!(selector)});
        return el ? el.getAttribute(#{Jason.encode!(attribute)}) : null;
      })()
      """

      with {:ok, session, %{result: value}} <- evaluate(session, script, opts) do
        {:ok, session, %{value: value}}
      end
    end)
  end

  @doc "Checks whether an element exists and is visible."
  @spec is_visible(Session.t(), String.t(), keyword()) :: {:ok, Session.t(), map()} | {:error, term()}
  # credo:disable-for-next-line Credo.Check.Readability.PredicateFunctionNames
  def is_visible(%Session{} = session, selector, opts \\ []) do
    command_or_fallback(session, :is_visible, Keyword.put(opts, :selector, selector), fn ->
      script = """
      (() => {
        const el = document.querySelector(#{Jason.encode!(selector)});
        if (!el) return {exists: false, visible: false};
        const style = window.getComputedStyle(el);
        return {
          exists: true,
          visible: el.offsetParent !== null && style.visibility !== "hidden" && style.display !== "none"
        };
      })()
      """

      evaluate(session, script, opts)
    end)
  end

  @doc "Returns the current session status, including URL, title, and liveness."
  @spec get_status(Session.t(), keyword()) :: {:ok, Session.t(), map()} | {:error, term()}
  def get_status(%Session{} = session, opts \\ []) do
    with {:ok, session, url_result} <- get_url(session, opts),
         {:ok, session, title_result} <- get_title(session, opts) do
      {:ok, session,
       %{
         alive: true,
         url: url_result[:url] || url_result["url"],
         title: title_result[:title] || title_result["title"],
         adapter: session.adapter |> to_string()
       }}
    else
      {:error, _reason} ->
        {:ok, session, %{alive: false, url: nil, title: nil, adapter: session.adapter |> to_string()}}
    end
  end

  @doc "Returns an agent-oriented page snapshot with ref metadata when supported."
  @spec snapshot(Session.t(), keyword()) :: {:ok, Session.t(), map()} | {:error, term()}
  def snapshot(%Session{} = session, opts \\ []) do
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

      evaluate(session, script, opts)
    end)
  end

  @doc "Persists browser session state to disk."
  @spec save_state(Session.t(), String.t(), keyword()) :: {:ok, Session.t(), map()} | {:error, term()}
  def save_state(%Session{} = session, path, opts \\ []) do
    command(session, :save_state, Keyword.put(opts, :path, path))
  end

  @doc "Restores browser session state from disk."
  @spec load_state(Session.t(), String.t(), keyword()) :: {:ok, Session.t(), map()} | {:error, term()}
  def load_state(%Session{} = session, path, opts \\ []) do
    command(session, :load_state, Keyword.put(opts, :path, path))
  end

  @doc "Lists open browser tabs."
  @spec list_tabs(Session.t(), keyword()) :: {:ok, Session.t(), map()} | {:error, term()}
  def list_tabs(%Session{} = session, opts \\ []) do
    command(session, :list_tabs, opts)
  end

  @doc "Opens a new tab, optionally at a URL."
  @spec new_tab(Session.t(), String.t() | nil, keyword()) :: {:ok, Session.t(), map()} | {:error, term()}
  def new_tab(%Session{} = session, url \\ nil, opts \\ []) do
    command(session, :new_tab, Keyword.put(opts, :url, url))
  end

  @doc "Switches to a tab by index."
  @spec switch_tab(Session.t(), non_neg_integer(), keyword()) :: {:ok, Session.t(), map()} | {:error, term()}
  def switch_tab(%Session{} = session, index, opts \\ []) do
    command(session, :switch_tab, Keyword.put(opts, :index, index))
  end

  @doc "Closes the current tab or a specific tab by index."
  @spec close_tab(Session.t(), non_neg_integer() | nil, keyword()) ::
          {:ok, Session.t(), map()} | {:error, term()}
  def close_tab(%Session{} = session, index \\ nil, opts \\ []) do
    command(session, :close_tab, Keyword.put(opts, :index, index))
  end

  @doc "Returns captured browser console messages when supported by the adapter."
  @spec console(Session.t(), keyword()) :: {:ok, Session.t(), map()} | {:error, term()}
  def console(%Session{} = session, opts \\ []) do
    command(session, :console, opts)
  end

  @doc "Returns captured browser runtime errors when supported by the adapter."
  @spec errors(Session.t(), keyword()) :: {:ok, Session.t(), map()} | {:error, term()}
  def errors(%Session{} = session, opts \\ []) do
    command(session, :errors, opts)
  end

  defp fallback_select_option(%Session{} = session, selector, opts) do
    script =
      cond do
        is_binary(opts[:value]) ->
          """
          (() => {
            const select = document.querySelector(#{Jason.encode!(selector)});
            if (!select) return {selected: false, error: "Select element not found"};
            select.value = #{Jason.encode!(opts[:value])};
            select.dispatchEvent(new Event("change", {bubbles: true}));
            return {selected: true, value: #{Jason.encode!(opts[:value])}};
          })()
          """

        is_binary(opts[:label]) ->
          """
          (() => {
            const select = document.querySelector(#{Jason.encode!(selector)});
            if (!select) return {selected: false, error: "Select element not found"};
            const option = Array.from(select.options).find(o => o.text === #{Jason.encode!(opts[:label])} || o.label === #{Jason.encode!(opts[:label])});
            if (!option) return {selected: false, error: "Option not found"};
            select.value = option.value;
            select.dispatchEvent(new Event("change", {bubbles: true}));
            return {selected: true, value: option.value, label: #{Jason.encode!(opts[:label])}};
          })()
          """

        is_integer(opts[:index]) ->
          """
          (() => {
            const select = document.querySelector(#{Jason.encode!(selector)});
            if (!select) return {selected: false, error: "Select element not found"};
            select.selectedIndex = #{opts[:index]};
            select.dispatchEvent(new Event("change", {bubbles: true}));
            return {selected: true, index: #{opts[:index]}, value: select.value};
          })()
          """

        true ->
          """
          (() => ({selected: false, error: "Must provide value, label, or index"}))()
          """
      end

    evaluate(session, script, opts)
  end

  defp build_scroll_script(opts) do
    cond do
      selector = opts[:selector] ->
        scroll_to_selector_script(selector)

      direction = opts[:direction] ->
        scroll_direction_script(direction)

      true ->
        scroll_coordinates_script(opts[:x] || 0, opts[:y] || 0)
    end
  end

  defp scroll_to_selector_script(selector) do
    """
    (() => {
      const el = document.querySelector(#{Jason.encode!(selector)});
      if (!el) return {scrolled: false, error: "Element not found"};
      el.scrollIntoView({behavior: "instant", block: "center"});
      return {scrolled: true, selector: #{Jason.encode!(selector)}};
    })()
    """
  end

  defp scroll_direction_script(direction) do
    {x, y} = direction_delta(direction)

    """
    (() => {
      window.scrollBy(#{x}, #{y});
      return {scrolled: true, direction: #{Jason.encode!(to_string(direction))}};
    })()
    """
  end

  defp scroll_coordinates_script(x, y) do
    """
    (() => {
      window.scrollBy(#{x}, #{y});
      return {scrolled: true, x: #{x}, y: #{y}};
    })()
    """
  end

  defp direction_delta(:top), do: {0, -1_000_000}
  defp direction_delta(:bottom), do: {0, 1_000_000}
  defp direction_delta(:left), do: {-1_000_000, 0}
  defp direction_delta(:right), do: {1_000_000, 0}
  defp direction_delta(_direction), do: {0, 0}

  defp get_all_text(session, selector, opts) do
    script = """
    (() => Array.from(document.querySelectorAll(#{Jason.encode!(selector)})).map(el => el.innerText || ""))()
    """

    with {:ok, session, %{result: texts}} <- evaluate(session, script, opts) do
      {:ok, session, %{texts: texts}}
    end
  end

  defp get_single_text(session, selector, opts) do
    script = """
    (() => {
      const el = document.querySelector(#{Jason.encode!(selector)});
      return el ? el.innerText || "" : null;
    })()
    """

    with {:ok, session, %{result: text}} <- evaluate(session, script, opts) do
      {:ok, session, %{text: text}}
    end
  end

  defp query_elements(session, selector, limit, opts) do
    script = """
    (() => {
      const selector = #{Jason.encode!(selector)};
      const limit = #{limit};
      return Array.from(document.querySelectorAll(selector)).slice(0, limit).map((el, i) => ({
        index: i,
        tag: el.tagName.toLowerCase(),
        id: el.id || null,
        classes: Array.from(el.classList),
        text: el.innerText?.substring(0, 100) || ""
      }));
    })()
    """

    case evaluate(session, script, opts) do
      {:ok, session, result} when is_map(result) ->
        case result[:result] || result["result"] do
          elements when is_list(elements) -> {:ok, session, elements}
          _ -> {:error, Error.adapter_error("Query script did not return an element list", %{result: result})}
        end

      error ->
        error
    end
  end

  defp query_count(session, selector, opts) do
    if command_supported?(session) do
      with {:ok, session, result} <- command(session, :count, selector: selector, timeout: opts[:timeout]),
           count when is_integer(count) <- result[:count] || result["count"] do
        {:ok, session, count}
      else
        _ -> {:error, :count_unavailable}
      end
    else
      {:error, :count_unsupported}
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

  defp normalize_timeout(opts), do: Keyword.put_new(opts, :timeout, @default_timeout)
end
