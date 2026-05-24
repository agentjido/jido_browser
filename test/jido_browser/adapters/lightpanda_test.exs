defmodule Jido.Browser.Adapters.LightpandaTest do
  use ExUnit.Case, async: false

  alias Jido.Browser
  alias Jido.Browser.Adapters.Lightpanda
  alias Jido.Browser.Error
  alias Jido.Browser.Pool
  alias Jido.Browser.Session

  @owner_key {__MODULE__, :owner}
  @png <<137, 80, 78, 71, 13, 10, 26, 10>>

  defmodule FakeLightCDP do
    def start(opts) do
      session = %{fake: :session, id: System.unique_integer([:positive])}
      send(owner(), {:light_cdp_start, opts, session})
      {:ok, session}
    end

    def new_page(session) do
      send(owner(), {:light_cdp_new_page, session})
      {:ok, %{fake: :page}}
    end

    def stop(session) do
      send(owner(), {:light_cdp_stop, session})
      :ok
    end

    defp owner, do: :persistent_term.get({Jido.Browser.Adapters.LightpandaTest, :owner})
  end

  defmodule FakePage do
    @png <<137, 80, 78, 71, 13, 10, 26, 10>>

    def navigate(page, url, opts) do
      send(owner(), {:page_navigate, page, url, opts})
      :ok
    end

    def click(page, selector, opts) do
      send(owner(), {:page_click, page, selector, opts})
      :ok
    end

    def fill(page, selector, text, opts) do
      send(owner(), {:page_fill, page, selector, text, opts})
      :ok
    end

    def screenshot(page, opts) do
      send(owner(), {:page_screenshot, page, opts})
      {:ok, @png}
    end

    def content(page) do
      send(owner(), {:page_content, page})

      {:ok,
       """
       <html>
         <head><title>Lightpanda Fixture</title></head>
         <body><main><h1>Hello</h1><p>World</p></main></body>
       </html>
       """}
    end

    def evaluate(page, script, opts) do
      send(owner(), {:page_evaluate, page, script, opts})
      {:ok, %{"answer" => 42}}
    end

    defp owner, do: :persistent_term.get({Jido.Browser.Adapters.LightpandaTest, :owner})
  end

  setup do
    old_config = Application.get_env(:jido_browser, :lightpanda, [])
    old_telemetry = System.get_env("LIGHTPANDA_DISABLE_TELEMETRY")
    :persistent_term.put(@owner_key, self())

    on_exit(fn ->
      Application.put_env(:jido_browser, :lightpanda, old_config)
      restore_env("LIGHTPANDA_DISABLE_TELEMETRY", old_telemetry)
      :persistent_term.erase(@owner_key)
    end)

    :ok
  end

  describe "start_session/1" do
    test "starts LightCDP with the configured Lightpanda binary and disables telemetry by default" do
      with_binary(fn binary ->
        with_lightpanda_config([binary_path: binary, light_cdp_module: FakeLightCDP, page_module: FakePage], fn ->
          assert {:ok, %Session{} = session} = Lightpanda.start_session(port: 9333, server_timeout: 7)

          assert session.adapter == Lightpanda
          assert session.connection.binary == binary
          assert session.connection.current_url == nil
          assert session.connection.light_cdp_module == FakeLightCDP
          assert session.connection.page_module == FakePage
          assert session.capabilities.limited == true

          assert_receive {:light_cdp_start, opts, %{fake: :session}}
          assert opts[:binary] == binary
          assert opts[:port] == 9333
          assert opts[:timeout] == 7
          assert System.get_env("LIGHTPANDA_DISABLE_TELEMETRY") == "true"

          assert_receive {:light_cdp_new_page, %{fake: :session}}
        end)
      end)
    end

    test "returns a clear error when light_cdp is not available" do
      with_binary(fn binary ->
        with_lightpanda_config([binary_path: binary, light_cdp_module: MissingLightCDP, page_module: FakePage], fn ->
          assert {:error, %Error.AdapterError{} = error} = Lightpanda.start_session([])
          assert error.message =~ "light_cdp optional dependency"
        end)
      end)
    end
  end

  describe "warm pools" do
    test "start_session checks out a prestarted Lightpanda session from the pool" do
      with_binary(fn binary ->
        with_lightpanda_config([binary_path: binary, light_cdp_module: FakeLightCDP, page_module: FakePage], fn ->
          pool_name = unique_pool_name()
          assert {:ok, pool} = Browser.start_pool(adapter: Lightpanda, name: pool_name, size: 1)
          on_exit(fn -> Browser.stop_pool(pool) end)

          assert_receive {:light_cdp_start, _opts, first_cdp_session}
          assert_receive {:light_cdp_new_page, ^first_cdp_session}

          assert {:ok, session} = Browser.start_session(adapter: Lightpanda, pool: pool_name)
          assert session.adapter == Lightpanda
          assert session.runtime.pooled == true
          assert session.connection.cdp_session == first_cdp_session

          assert {:ok, session, %{url: "https://example.com"}} =
                   Browser.navigate(session, "https://example.com")

          assert_receive {:page_navigate, %{fake: :page}, "https://example.com", [timeout: 30_000]}

          assert :ok = Browser.end_session(session)
          assert_receive {:light_cdp_stop, ^first_cdp_session}, 1_000
        end)
      end)
    end

    test "supervised pool child works with the Lightpanda adapter" do
      with_binary(fn binary ->
        with_lightpanda_config([binary_path: binary, light_cdp_module: FakeLightCDP, page_module: FakePage], fn ->
          pool_name = unique_pool_name()
          start_supervised!({Pool, adapter: Lightpanda, name: pool_name, size: 1})

          assert_receive {:light_cdp_start, _opts, cdp_session}
          assert_receive {:light_cdp_new_page, ^cdp_session}

          assert {:ok, session} = Browser.start_session(adapter: Lightpanda, pool: pool_name)

          assert {:ok, _session, %{result: %{"answer" => 42}}} =
                   Browser.evaluate(session, "answer()")

          assert :ok = Browser.end_session(session)
        end)
      end)
    end
  end

  describe "adapter operations" do
    test "delegate to LightCDP.Page and keep the session contract" do
      session = start_fake_session!()
      url = "https://example.com"

      assert {:ok, session, %{url: ^url}} = Lightpanda.navigate(session, url, timeout: 1234)
      assert session.connection.current_url == url
      assert_receive {:page_navigate, %{fake: :page}, ^url, [timeout: 1234]}

      assert {:ok, ^session, %{selector: "#submit"}} = Lightpanda.click(session, "#submit", timeout: 567)
      assert_receive {:page_click, %{fake: :page}, "#submit", [timeout: 567]}

      assert {:ok, ^session, %{selector: "#email"}} = Lightpanda.type(session, "#email", "a@example.com", [])
      assert_receive {:page_fill, %{fake: :page}, "#email", "a@example.com", [timeout: 30_000]}

      assert {:ok, ^session, %{bytes: @png, mime: "image/png", format: :png}} = Lightpanda.screenshot(session, [])
      assert_receive {:page_screenshot, %{fake: :page}, [timeout: 30_000]}

      assert {:ok, ^session, %{result: %{"answer" => 42}}} = Lightpanda.evaluate(session, "answer()", timeout: 99)
      assert_receive {:page_evaluate, %{fake: :page}, "answer()", [timeout: 99]}

      assert :ok = Lightpanda.end_session(session)
      assert_receive {:light_cdp_stop, %{fake: :session}}
    end

    test "rejects non-PNG screenshots" do
      session = start_fake_session!()

      assert {:error, %Error.AdapterError{} = error} = Lightpanda.screenshot(session, format: :jpeg)
      assert error.details[:requested_format] == :jpeg
      assert error.details[:supported_formats] == [:png]
    end
  end

  describe "extract_content/2" do
    test "extracts selected HTML, text, and markdown from LightCDP content" do
      session = start_fake_session!()

      assert {:ok, ^session, %{format: :html, content: html}} =
               Lightpanda.extract_content(session, selector: "main", format: :html)

      assert html =~ "<main>"
      assert html =~ "<h1>Hello</h1>"

      assert {:ok, ^session, %{format: :text, content: text}} =
               Lightpanda.extract_content(session, selector: "main", format: :text)

      assert text =~ "Hello"
      assert text =~ "World"
      refute text =~ "<"

      assert {:ok, ^session, %{format: :markdown, content: markdown}} = Lightpanda.extract_content(session, [])
      assert markdown =~ "Hello"
      assert markdown =~ "World"

      assert_receive {:page_content, %{fake: :page}}
    end
  end

  defp start_fake_session! do
    with_binary(fn binary ->
      with_lightpanda_config([binary_path: binary, light_cdp_module: FakeLightCDP, page_module: FakePage], fn ->
        assert {:ok, session} = Lightpanda.start_session([])
        flush_messages()
        session
      end)
    end)
  end

  defp flush_messages do
    receive do
      _ -> flush_messages()
    after
      0 -> :ok
    end
  end

  defp with_lightpanda_config(config, fun) do
    Application.put_env(:jido_browser, :lightpanda, config)
    fun.()
  end

  defp with_binary(fun) do
    path = Path.join(System.tmp_dir!(), "jido_browser_lightpanda_#{System.unique_integer([:positive])}")
    File.write!(path, "lightpanda")
    File.chmod!(path, 0o755)

    try do
      fun.(path)
    after
      File.rm(path)
    end
  end

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)

  defp unique_pool_name do
    "lightpanda-pool-#{System.unique_integer([:positive])}"
  end
end
