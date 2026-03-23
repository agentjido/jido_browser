defmodule Jido.Browser.Adapters.Web.CLI do
  @moduledoc false

  alias Jido.Browser.Installer

  @default_timeout 30_000
  @default_warmup_html """
  <!DOCTYPE html>
  <html>
    <head><title>Jido Browser Web Pool Warmup</title></head>
    <body>
      <p>Warmup page for local Web adapter profile initialization.</p>
    </body>
  </html>
  """

  @doc false
  @spec execute(String.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def execute(profile, %{"action" => "navigate", "url" => url}, opts) do
    with {:ok, output} <- run_web_command([url], Keyword.put(opts, :profile, profile)) do
      {:ok, %{"url" => url, "content" => output}}
    end
  end

  def execute(profile, %{"action" => "click", "selector" => selector} = payload, opts) do
    with {:ok, url} <- current_url(payload),
         args <- [url, "--click", selector] |> maybe_append("--text", payload["text"]),
         {:ok, output} <- run_web_command(args, Keyword.put(opts, :profile, profile)) do
      {:ok, %{"selector" => selector, "content" => output}}
    end
  end

  def execute(profile, %{"action" => "type", "selector" => selector, "text" => text} = payload, opts) do
    with {:ok, url} <- current_url(payload),
         {:ok, output} <-
           run_web_command([url, "--fill", "#{selector}=#{text}"], Keyword.put(opts, :profile, profile)) do
      {:ok, %{"selector" => selector, "content" => output}}
    end
  end

  def execute(profile, %{"action" => "screenshot", "format" => "png"} = payload, opts) do
    with {:ok, url} <- current_url(payload) do
      screenshot(profile, url, payload, opts)
    end
  end

  def execute(profile, %{"action" => "extract_content"} = payload, opts) do
    with {:ok, url} <- current_url(payload),
         {:ok, content} <-
           run_web_command(
             build_extract_args(url, payload["format"] || :markdown),
             Keyword.put(opts, :profile, profile)
           ) do
      {:ok, %{"content" => content, "format" => payload["format"] || :markdown}}
    end
  end

  def execute(profile, %{"action" => "evaluate", "script" => script} = payload, opts) do
    with {:ok, url} <- current_url(payload),
         {:ok, output} <- run_web_command([url, "--js", script], Keyword.put(opts, :profile, profile)) do
      {:ok, %{"result" => parse_js_result(output)}}
    end
  end

  def execute(_profile, _payload, _opts), do: {:error, :unsupported_action}

  @doc false
  @spec warm_profile(String.t(), keyword()) :: :ok | {:error, term()}
  def warm_profile(profile, opts) do
    File.mkdir_p!(profile_path(profile))

    if warmup_url = opts[:warmup_url] do
      run_warmup_command(profile, warmup_url, opts)
    else
      with_default_warmup_url(fn default_warmup_url ->
        run_warmup_command(profile, default_warmup_url, opts)
      end)
    end
  end

  @doc false
  @spec delete_profile(String.t()) :: :ok
  def delete_profile(profile) do
    _ = File.rm_rf(profile_path(profile))
    :ok
  end

  @doc false
  @spec profile_path(String.t()) :: String.t()
  def profile_path(profile) do
    Path.join(profile_root(), profile)
  end

  @doc false
  @spec find_binary(keyword()) :: {:ok, String.t()} | {:error, String.t()}
  def find_binary(opts \\ []) do
    case opts[:binary] || config(:binary_path) do
      path when is_binary(path) and path != "" ->
        {:ok, path}

      _ ->
        find_web_in_path_or_install()
    end
  end

  defp current_url(%{"current_url" => url}) when is_binary(url) and url != "", do: {:ok, url}
  defp current_url(_payload), do: {:error, :no_current_url}

  defp build_extract_args(url, :html), do: [url, "--html"]
  defp build_extract_args(url, "html"), do: [url, "--html"]
  defp build_extract_args(url, :text), do: [url, "--text"]
  defp build_extract_args(url, "text"), do: [url, "--text"]
  defp build_extract_args(url, :markdown), do: [url]
  defp build_extract_args(url, "markdown"), do: [url]
  defp build_extract_args(url, _other), do: [url]

  defp parse_js_result(result) do
    case Jason.decode(result) do
      {:ok, decoded} -> decoded
      {:error, _} -> result
    end
  end

  defp run_warmup_command(profile, warmup_url, opts) do
    case run_web_command([warmup_url], Keyword.put(opts, :profile, profile)) do
      {:ok, _output} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp with_default_warmup_url(fun) when is_function(fun, 1) do
    with {:ok, listener} <- start_warmup_listener(),
         {:ok, {_, port}} <- :inet.sockname(listener),
         {:ok, task} <- Task.start_link(fn -> warmup_accept_loop(listener) end) do
      try do
        fun.("http://127.0.0.1:#{port}/")
      after
        :gen_tcp.close(listener)
        Process.exit(task, :normal)
      end
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp start_warmup_listener do
    :gen_tcp.listen(0, [
      :binary,
      {:active, false},
      {:packet, :raw},
      {:reuseaddr, true},
      {:ip, {127, 0, 0, 1}}
    ])
  end

  defp warmup_accept_loop(listener) do
    case :gen_tcp.accept(listener) do
      {:ok, socket} ->
        Task.start(fn -> respond_to_warmup_request(socket) end)
        warmup_accept_loop(listener)

      {:error, :closed} ->
        :ok

      {:error, _reason} ->
        :ok
    end
  end

  defp respond_to_warmup_request(socket) do
    _ = read_warmup_request(socket)
    _ = :gen_tcp.send(socket, warmup_response())
    :gen_tcp.close(socket)
  end

  defp read_warmup_request(socket, acc \\ "") do
    if String.contains?(acc, "\r\n\r\n") do
      :ok
    else
      case :gen_tcp.recv(socket, 0, 1_000) do
        {:ok, chunk} -> read_warmup_request(socket, acc <> chunk)
        {:error, _reason} -> :ok
      end
    end
  end

  defp warmup_response do
    body = @default_warmup_html

    [
      "HTTP/1.1 200 OK\r\n",
      "content-type: text/html; charset=utf-8\r\n",
      "content-length: #{byte_size(body)}\r\n",
      "connection: close\r\n\r\n",
      body
    ]
  end

  defp screenshot(profile, url, payload, opts) do
    with_tmp_file("jido_browser_web_pool", ".png", fn path ->
      args =
        [url, "--screenshot", path]
        |> maybe_append_flag(payload["full_page"])

      with {:ok, _output} <- run_web_command(args, Keyword.put(opts, :profile, profile)),
           {:ok, bytes} <- File.read(path) do
        {:ok, %{"bytes" => bytes, "mime" => "image/png", "format" => "png"}}
      else
        {:error, reason} when is_atom(reason) ->
          {:error, {:screenshot_read_failed, reason}}

        {:error, reason} ->
          {:error, reason}
      end
    end)
  end

  defp run_web_command(args, opts) do
    with {:ok, binary} <- find_binary(opts) do
      timeout = opts[:timeout] || @default_timeout
      profile = opts[:profile]
      full_args = if profile, do: ["--profile", profile | args], else: args

      try do
        run_with_timeout(binary, full_args, timeout)
      rescue
        error -> {:error, Exception.message(error)}
      end
    end
  end

  defp run_with_timeout(binary, args, timeout) do
    port =
      Port.open({:spawn_executable, binary}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        args: args
      ])

    collect_output(port, [], timeout)
  end

  defp collect_output(port, acc, timeout) do
    receive do
      {^port, {:data, data}} ->
        collect_output(port, [acc | [data]], timeout)

      {^port, {:exit_status, 0}} ->
        {:ok, acc |> IO.iodata_to_binary() |> String.trim()}

      {^port, {:exit_status, code}} ->
        output = IO.iodata_to_binary(acc)
        {:error, "web exited with code #{code}: #{output}"}
    after
      timeout ->
        Port.close(port)
        {:error, "Command timed out after #{timeout}ms"}
    end
  end

  defp maybe_append(args, _flag, nil), do: args
  defp maybe_append(args, flag, value), do: args ++ [flag, value]

  defp maybe_append_flag(args, true), do: args ++ ["--full-page"]
  defp maybe_append_flag(args, _other), do: args

  defp find_web_in_path_or_install do
    case System.find_executable("web") do
      path when is_binary(path) ->
        {:ok, path}

      nil ->
        jido_path = Path.join(Installer.default_install_path(), "web")

        if File.exists?(jido_path) do
          {:ok, jido_path}
        else
          {:error, "web binary not found. Install with: mix jido_browser.install web"}
        end
    end
  end

  defp profile_root do
    config(:profile_root, Path.join(System.user_home!(), ".web-firefox/profiles"))
  end

  defp config(key, default \\ nil) do
    :jido_browser
    |> Application.get_env(:web, [])
    |> Keyword.get(key, default)
  end

  defp with_tmp_file(prefix, suffix, fun) do
    path = Path.join(System.tmp_dir!(), "#{prefix}_#{System.unique_integer([:positive])}#{suffix}")

    try do
      fun.(path)
    after
      File.rm(path)
    end
  end
end
