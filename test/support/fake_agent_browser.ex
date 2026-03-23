defmodule Jido.Browser.TestSupport.FakeAgentBrowser do
  @moduledoc false

  @spec with_binary(atom(), (String.t(), String.t() -> result)) :: result when result: var
  def with_binary(mode, fun) when is_atom(mode) and is_function(fun, 2) do
    tmp_dir = Path.join("/tmp", "jbfa_#{System.unique_integer([:positive])}")

    binary = Path.join(tmp_dir, "agent-browser")
    socket_dir = Path.join(tmp_dir, "sockets")
    old_socket_dir = System.get_env("AGENT_BROWSER_SOCKET_DIR")

    File.mkdir_p!(socket_dir)
    File.write!(binary, script(mode))
    File.chmod!(binary, 0o755)
    System.put_env("AGENT_BROWSER_SOCKET_DIR", socket_dir)

    try do
      fun.(binary, socket_dir)
    after
      restore_env("AGENT_BROWSER_SOCKET_DIR", old_socket_dir)
      File.rm_rf(tmp_dir)
    end
  end

  defp restore_env(_key, nil), do: System.delete_env("AGENT_BROWSER_SOCKET_DIR")
  defp restore_env(key, value), do: System.put_env(key, value)

  defp script(mode) do
    """
    #!/usr/bin/env elixir
    mode = #{inspect(to_string(mode))}

    defmodule FakeAgentBrowserDaemon do
      def run("exit_on_start") do
        IO.binwrite(:stderr, "boot failure")
        System.halt(13)
      end

      def run(mode) do
        session_id = System.fetch_env!("AGENT_BROWSER_SESSION")
        socket_dir = System.fetch_env!("AGENT_BROWSER_SOCKET_DIR")
        socket_path = Path.join(socket_dir, "\#{session_id}.sock")

        File.rm(socket_path)
        File.mkdir_p!(Path.dirname(socket_path))

        {:ok, listener} =
          :gen_tcp.listen(0, [
            :binary,
            packet: :line,
            active: false,
            ifaddr: {:local, String.to_charlist(socket_path)}
          ])

        accept_loop(listener, %{mode: mode, current_url: nil, action_counts: %{}})
      end

      defp accept_loop(listener, state) do
        case :gen_tcp.accept(listener) do
          {:ok, socket} ->
            {state, halt_code} = handle_socket(socket, state)
            :gen_tcp.close(socket)

            if is_integer(halt_code) do
              System.halt(halt_code)
            else
              accept_loop(listener, state)
            end

          {:error, reason} ->
            IO.binwrite(:stderr, "accept failed: \#{inspect(reason)}")
            System.halt(91)
        end
      end

      defp handle_socket(socket, state) do
        case :gen_tcp.recv(socket, 0, 30_000) do
          {:ok, line} ->
            action = capture(line, ~r/"action"\\s*:\\s*"([^"]+)"/)
            url = capture(line, ~r/"url"\\s*:\\s*"([^"]+)"/)
            respond(socket, state, action, url)

          {:error, reason} ->
            IO.binwrite(:stderr, "recv failed: \#{inspect(reason)}")
            {state, 92}
        end
      end

      defp respond(socket, %{mode: "never_ready"} = state, "title", _url) do
        send_response(socket, false, nil, "booting")
        {state, nil}
      end

      defp respond(socket, %{mode: "exit_after_ready"} = state, "title", _url) do
        send_response(socket, true, %{"title" => title_for(state.current_url), "url" => state.current_url}, nil)
        {state, 55}
      end

      defp respond(socket, %{mode: "flaky_navigate", action_counts: counts} = state, "navigate", url) do
        attempts = Map.update(counts, "navigate", 1, &(&1 + 1))

        if attempts["navigate"] == 1 do
          send_response(socket, false, nil, "connection refused")
          {%{state | action_counts: attempts}, nil}
        else
          send_response(socket, true, %{"url" => url}, nil)
          {%{state | action_counts: attempts, current_url: url}, nil}
        end
      end

      defp respond(socket, state, "navigate", url) when state.mode == "exit_on_navigate" do
        send_response(socket, true, %{"url" => url}, nil)
        {%{state | current_url: url}, 56}
      end

      defp respond(socket, state, "navigate", url) do
        send_response(socket, true, %{"url" => url}, nil)
        {%{state | current_url: url}, nil}
      end

      defp respond(socket, state, "title", _url) do
        send_response(socket, true, %{"title" => title_for(state.current_url), "url" => state.current_url}, nil)
        {state, nil}
      end

      defp respond(socket, state, "close", _url) do
        send_response(socket, true, %{}, nil)
        {state, 0}
      end

      defp respond(socket, state, _action, _url) do
        send_response(socket, true, %{}, nil)
        {state, nil}
      end

      defp send_response(socket, success, data, error) do
        payload =
          %{}
          |> maybe_put("success", success)
          |> maybe_put("data", data)
          |> maybe_put("error", error)
          |> encode_map()

        :ok = :gen_tcp.send(socket, payload <> "\\n")
      end

      defp maybe_put(map, _key, nil), do: map
      defp maybe_put(map, key, value), do: Map.put(map, key, value)

      defp encode_map(map) do
        map
        |> Enum.map_join(",", fn {key, value} ->
          "\\\"\#{key}\\\":\#{encode_value(value)}"
        end)
        |> then(&"{\#{&1}}")
      end

      defp encode_value(map) when is_map(map), do: encode_map(map)
      defp encode_value(nil), do: "null"
      defp encode_value(true), do: "true"
      defp encode_value(false), do: "false"
      defp encode_value(value) when is_binary(value), do: "\\\"\#{escape(value)}\\\""
      defp encode_value(value), do: to_string(value)

      defp escape(value) do
        value
        |> String.replace("\\\\", "\\\\\\\\")
        |> String.replace("\\\"", "\\\\\\\"")
      end

      defp capture(line, regex) do
        case Regex.run(regex, line, capture: :all_but_first) do
          [value] -> unescape(value)
          _ -> nil
        end
      end

      defp unescape(value) do
        value
        |> String.replace("\\\\/", "/")
        |> String.replace("\\\\\\"", "\\\"")
        |> String.replace("\\\\\\\\", "\\\\")
      end

      defp title_for(nil), do: "Ready"
      defp title_for(url), do: "Title for \#{url}"
    end

    FakeAgentBrowserDaemon.run(mode)
    """
  end
end
