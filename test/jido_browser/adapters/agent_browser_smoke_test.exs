defmodule Jido.Browser.Adapters.AgentBrowserSmokeTest do
  @moduledoc """
  Required AgentBrowser smoke coverage against a local fixture server.

  Run with:

      JIDO_BROWSER_REQUIRE_AGENT_BROWSER=true \
        mix test test/jido_browser/adapters/agent_browser_smoke_test.exs \
        --include integration --only agent_browser_smoke
  """

  use ExUnit.Case, async: false

  alias Jido.Browser
  alias Jido.Browser.Adapters.AgentBrowser
  alias Jido.Browser.AgentBrowser.Runtime
  alias Jido.Browser.TestSupport.IntegrationTestServer

  @availability (case Runtime.find_binary() do
                   {:ok, binary} -> Runtime.ensure_supported_version(binary)
                   {:error, reason} -> {:error, reason}
                 end)

  @moduletag :integration
  @moduletag :agent_browser
  @moduletag :agent_browser_smoke
  @moduletag timeout: 180_000

  if @availability != :ok do
    if System.get_env("JIDO_BROWSER_REQUIRE_AGENT_BROWSER") == "true" do
      raise "Required AgentBrowser smoke suite is unavailable: #{inspect(@availability)}"
    else
      @moduletag skip: "agent-browser smoke unavailable: #{inspect(@availability)}"
    end
  end

  @command_timeout 60_000

  setup_all do
    {:ok, server} = IntegrationTestServer.start()
    on_exit(fn -> IntegrationTestServer.stop(server) end)
    {:ok, base_url: IntegrationTestServer.base_url(server)}
  end

  test "starts, navigates, snapshots, types, clicks, reads, and closes", %{base_url: base_url} do
    assert {:ok, session} =
             Browser.start_session(
               adapter: AgentBrowser,
               headless: true,
               allowed_domains: ["127.0.0.1"],
               timeout: @command_timeout
             )

    on_exit(fn -> assert :ok = end_session_if_running(session) end)

    assert {:ok, session, _navigate_result} =
             Browser.navigate(session, "#{base_url}/refs", timeout: @command_timeout)

    assert {:ok, session, snapshot_result} = Browser.snapshot(session, timeout: @command_timeout)
    refs = fetch_value(snapshot_result, :refs)

    assert is_binary(fetch_value(snapshot_result, :snapshot))
    assert is_map(refs)
    assert map_size(refs) > 0

    input_ref = ref_from_refs!(refs, "Ref Input Marker")
    button_ref = ref_from_refs!(refs, "Use Ref Button Marker")

    assert {:ok, session, _type_result} =
             Browser.type(session, input_ref, "supported smoke", clear: true, timeout: @command_timeout)

    assert {:ok, session, _click_result} =
             Browser.click(session, button_ref, timeout: @command_timeout)

    assert {:ok, session, read_result} =
             Browser.get_text(session, "#ref-output", timeout: @command_timeout)

    assert fetch_value(read_result, :text) == "Submitted: supported smoke"
    assert :ok = Browser.end_session(session)
    assert_eventually(fn -> session_stopped?(session) end)
  end

  defp end_session_if_running(session) do
    case Runtime.lookup_session_server(session.id) do
      {:ok, _pid} -> Browser.end_session(session)
      :error -> :ok
    end
  catch
    :exit, {:noproc, _call} -> :ok
  end

  defp session_stopped?(session) do
    Runtime.lookup_session_server(session.id) == :error and
      not File.exists?(Runtime.pid_path(session.id)) and
      not File.exists?(Runtime.socket_path(session.id))
  end

  defp assert_eventually(condition, timeout \\ 5_000) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_assert_eventually(condition, deadline)
  end

  defp do_assert_eventually(condition, deadline) do
    if condition.() do
      :ok
    else
      if System.monotonic_time(:millisecond) >= deadline do
        flunk("AgentBrowser session did not close before the timeout")
      else
        Process.sleep(20)
        do_assert_eventually(condition, deadline)
      end
    end
  end

  defp ref_from_refs!(refs, marker) do
    refs
    |> Enum.find_value(fn {ref, entry} ->
      name = fetch_value(entry, :name)

      if is_binary(name) and String.contains?(String.downcase(name), String.downcase(marker)) do
        normalize_ref(ref)
      end
    end)
    |> case do
      nil -> flunk("Could not find ref for #{inspect(marker)} in refs:\n#{inspect(refs, pretty: true)}")
      ref -> ref
    end
  end

  defp normalize_ref("@" <> _ = ref), do: ref
  defp normalize_ref(ref), do: "@#{ref}"

  defp fetch_value(map, key), do: Map.fetch!(map, key)
end
