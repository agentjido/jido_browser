defmodule Jido.Browser.DeprecationsTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Jido.Browser.Adapters.AgentBrowser
  alias Jido.Browser.Adapters.Lightpanda
  alias Jido.Browser.Adapters.Vibium
  alias Jido.Browser.Adapters.Web
  alias Jido.Browser.Deprecations
  alias Jido.Browser.TestSupport.FakeWebBinary
  alias Jido.Browser.Vendor.BrowseyHttp
  alias Jido.Browser.WebFetch.Backends.Browsey
  alias Jido.Browser.WebFetch.Backends.Req

  defmodule TestBrowseyClient do
    def get(url, _opts) do
      {:ok,
       %{
         status: 200,
         headers: %{"content-type" => ["text/html"]},
         body: "<html><head><title>Browsey test</title></head><body>ok</body></html>",
         final_uri: URI.parse(url)
       }}
    end
  end

  setup do
    old_adapter = Application.get_env(:jido_browser, :adapter, :__missing__)
    old_web_fetch = Application.get_env(:jido_browser, :web_fetch, :__missing__)

    Application.put_env(:jido_browser, :adapter, AgentBrowser)
    Application.delete_env(:jido_browser, :web_fetch)
    capture_log(&restart_application!/0)

    on_exit(fn ->
      restore_env(:adapter, old_adapter)
      restore_env(:web_fetch, old_web_fetch)
      capture_log(&restart_application!/0)
    end)

    :ok
  end

  test "warns once for the Web adapter module and alias" do
    log =
      capture_log(fn ->
        assert :ok = Deprecations.warn(Web)
        assert :ok = Deprecations.warn(:web)
        assert :ok = Deprecations.warn(Web)
      end)

    assert warning_count(log, "Web adapter runtime") == 1
    assert log =~ inspect(Web)
    assert log =~ "removed in Jido Browser 3.0"
    assert log =~ inspect(AgentBrowser)
  end

  test "warns once for each BrowseyHttp backend name and alias" do
    log =
      capture_log(fn ->
        assert :ok = Deprecations.warn(:browsey)
        assert :ok = Deprecations.warn(Browsey)
        assert :ok = Deprecations.warn(BrowseyHttp)
      end)

    assert warning_count(log, "BrowseyHttp") == 1
    assert log =~ ":browsey web-fetch runtime"
    assert log =~ "removed in Jido Browser 3.0"
    assert log =~ inspect(Req)
    assert log =~ inspect(AgentBrowser)
  end

  test "serializes concurrent deprecated selections into one warning" do
    log =
      capture_log(fn ->
        1..100
        |> Task.async_stream(
          fn index ->
            selection = if rem(index, 2) == 0, do: Web, else: :web
            Deprecations.warn(selection)
          end,
          max_concurrency: 20,
          ordered: false
        )
        |> Enum.each(fn result -> assert result == {:ok, :ok} end)
      end)

    assert warning_count(log, "Web adapter runtime") == 1
  end

  test "does not warn for supported adapters and the Req backend" do
    log =
      capture_log(fn ->
        for selection <- [AgentBrowser, Lightpanda, Vibium, Req, :req] do
          assert :ok = Deprecations.warn(selection)
        end
      end)

    assert log == ""
  end

  test "warns for configured deprecated runtimes during application boot" do
    :ok = Application.stop(:jido_browser)
    Application.put_env(:jido_browser, :adapter, Web)
    Application.put_env(:jido_browser, :web_fetch, backend: :browsey)

    log = capture_log(&start_application!/0)

    assert warning_count(log, "Web adapter runtime") == 1
    assert warning_count(log, "BrowseyHttp") == 1

    repeated_log =
      capture_log(fn ->
        assert :ok = Deprecations.warn(Web)
        assert :ok = Deprecations.warn(:browsey)
      end)

    assert repeated_log == ""
  end

  test "worker restart preserves runtimes and warning state until a real application restart" do
    agent_browser_supervisor = Process.whereis(Jido.Browser.AgentBrowser.SessionTreeSupervisor)
    warm_pool_supervisor = Process.whereis(Jido.Browser.WarmPool.RootSupervisor)
    deprecations = Process.whereis(Deprecations)

    assert is_pid(agent_browser_supervisor)
    assert is_pid(warm_pool_supervisor)
    assert is_pid(deprecations)

    Application.put_env(:jido_browser, :adapter, Web)
    first_log = capture_log(fn -> assert :ok = Deprecations.warn(Web) end)

    restart_log =
      capture_log(fn ->
        ref = Process.monitor(deprecations)
        Process.exit(deprecations, :kill)
        assert_receive {:DOWN, ^ref, :process, ^deprecations, :killed}, 1_000
        assert is_pid(await_restarted_process(Deprecations, deprecations))
      end)

    restarted_deprecations = Process.whereis(Deprecations)
    repeated_log = capture_log(fn -> assert :ok = Deprecations.warn(Web) end)

    assert Process.whereis(Jido.Browser.AgentBrowser.SessionTreeSupervisor) == agent_browser_supervisor
    assert Process.whereis(Jido.Browser.WarmPool.RootSupervisor) == warm_pool_supervisor
    assert restarted_deprecations != deprecations
    assert warning_count(restart_log, "Web adapter runtime") == 0
    assert repeated_log == ""

    application_restart_log = capture_log(&restart_application!/0)
    after_application_restart_log = capture_log(fn -> assert :ok = Deprecations.warn(Web) end)

    assert warning_count(first_log, "Web adapter runtime") == 1
    assert warning_count(application_restart_log, "Web adapter runtime") == 1
    assert after_application_restart_log == ""
  end

  test "keeps Web session behavior and warns once across repeated sessions" do
    FakeWebBinary.with_binary(:normal, fn binary, _profile_root ->
      log =
        capture_log(fn ->
          assert {:ok, first_session} =
                   Jido.Browser.start_session(adapter: Web, binary: binary, profile: "deprecated-first")

          assert {:ok, _session, first_result} =
                   Jido.Browser.navigate(first_session, "https://example.com/first")

          assert first_result == %{content: "ok:https://example.com/first", url: "https://example.com/first"}
          assert :ok = Jido.Browser.end_session(first_session)

          assert {:ok, second_session} =
                   Jido.Browser.start_session(adapter: Web, binary: binary, profile: "deprecated-second")

          assert :ok = Jido.Browser.end_session(second_session)
        end)

      assert warning_count(log, "Web adapter runtime") == 1
    end)
  end

  test "keeps BrowseyHttp behavior and warns once for alias and module requests" do
    log =
      capture_log(fn ->
        for backend <- [:browsey, Browsey] do
          assert {:ok, result} =
                   Jido.Browser.web_fetch(
                     "https://example.com/#{inspect(backend)}",
                     backend: backend,
                     browsey: [client: TestBrowseyClient],
                     cache: false,
                     format: :text
                   )

          assert result.content == "Browsey test\nok"
        end
      end)

    assert warning_count(log, "BrowseyHttp") == 1
  end

  defp warning_count(log, text) do
    log
    |> String.split("\n")
    |> Enum.count(&String.contains?(&1, text))
  end

  defp await_restarted_process(name, old_pid, attempts \\ 100)

  defp await_restarted_process(_name, _old_pid, 0), do: flunk("process did not restart")

  defp await_restarted_process(name, old_pid, attempts) do
    case Process.whereis(name) do
      pid when is_pid(pid) and pid != old_pid ->
        pid

      _pid ->
        Process.sleep(10)
        await_restarted_process(name, old_pid, attempts - 1)
    end
  end

  defp restart_application! do
    case Application.stop(:jido_browser) do
      :ok -> start_application!()
      {:error, {:not_started, :jido_browser}} -> start_application!()
    end
  end

  defp start_application! do
    case Application.ensure_all_started(:jido_browser) do
      {:ok, _applications} -> :ok
      {:error, reason} -> raise "could not start jido_browser: #{inspect(reason)}"
    end
  end

  defp restore_env(key, :__missing__), do: Application.delete_env(:jido_browser, key)
  defp restore_env(key, value), do: Application.put_env(:jido_browser, key, value)
end
