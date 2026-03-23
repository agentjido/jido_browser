defmodule Jido.BrowserTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Jido.Browser.Pool
  alias Jido.Browser.Session

  describe "start_session/1" do
    test "creates a session with default adapter" do
      expect(Jido.Browser.Adapters.AgentBrowser, :start_session, fn opts ->
        Session.new(%{
          adapter: Jido.Browser.Adapters.AgentBrowser,
          connection: %{binary: opts[:binary] || "/usr/local/bin/agent-browser"},
          runtime: %{manager: self()},
          capabilities: %{native_snapshot: true},
          opts: Map.new(opts)
        })
      end)

      assert {:ok, %Session{adapter: Jido.Browser.Adapters.AgentBrowser}} =
               Jido.Browser.start_session()
    end

    test "accepts custom adapter" do
      expect(Jido.Browser.Adapters.Web, :start_session, fn _opts ->
        Session.new(%{
          adapter: Jido.Browser.Adapters.Web,
          connection: %{profile: "default"}
        })
      end)

      # Mock returns bare session, adapter wraps with {:ok, ...}
      assert {:ok, %Session{adapter: Jido.Browser.Adapters.Web}} =
               Jido.Browser.start_session(adapter: Jido.Browser.Adapters.Web)
    end
  end

  describe "pool management" do
    test "delegates start_pool to a pool-capable adapter" do
      expect(Jido.Browser.Adapters.AgentBrowser, :start_pool, fn opts ->
        assert opts[:name] == "default"
        assert opts[:size] == 2
        {:ok, self()}
      end)

      assert {:ok, pid} = Jido.Browser.start_pool(name: "default", size: 2)
      assert pid == self()
    end

    test "permits pooled sessions for a pool-capable adapter" do
      expect(Jido.Browser.Adapters.Web, :start_session, fn opts ->
        assert opts[:pool] == "default"

        Session.new(%{
          adapter: Jido.Browser.Adapters.Web,
          connection: %{profile: "pooled-default"}
        })
      end)

      assert {:ok, %Session{adapter: Jido.Browser.Adapters.Web}} =
               Jido.Browser.start_session(adapter: Jido.Browser.Adapters.Web, pool: "default")
    end

    test "public pool child spec is a supervisor with infinite shutdown" do
      child_spec = Pool.child_spec(name: :default, size: 2)

      assert child_spec.type == :supervisor
      assert child_spec.shutdown == :infinity
    end
  end

  describe "navigate/3" do
    test "delegates to adapter" do
      session = build_session()

      expect(Jido.Browser.Adapters.AgentBrowser, :navigate, fn ^session, url, _opts ->
        {:ok, session, %{url: url}}
      end)

      assert {:ok, ^session, %{url: "https://example.com"}} =
               Jido.Browser.navigate(session, "https://example.com")
    end
  end

  describe "click/3" do
    test "delegates to adapter" do
      session = build_session()

      expect(Jido.Browser.Adapters.AgentBrowser, :click, fn ^session, selector, _opts ->
        {:ok, session, %{selector: selector}}
      end)

      assert {:ok, ^session, %{selector: "button#submit"}} =
               Jido.Browser.click(session, "button#submit")
    end
  end

  describe "type/4" do
    test "delegates to adapter" do
      session = build_session()

      expect(Jido.Browser.Adapters.AgentBrowser, :type, fn ^session, selector, text, _opts ->
        {:ok, session, %{selector: selector, text: text}}
      end)

      assert {:ok, ^session, %{selector: "input#email"}} =
               Jido.Browser.type(session, "input#email", "test@example.com")
    end
  end

  describe "screenshot/2" do
    test "delegates to adapter" do
      session = build_session()
      png_bytes = <<137, 80, 78, 71>>

      expect(Jido.Browser.Adapters.AgentBrowser, :screenshot, fn ^session, _opts ->
        {:ok, session, %{bytes: png_bytes, mime: "image/png"}}
      end)

      assert {:ok, ^session, %{bytes: ^png_bytes, mime: "image/png"}} =
               Jido.Browser.screenshot(session)
    end
  end

  describe "extract_content/2" do
    test "delegates to adapter" do
      session = build_session()

      expect(Jido.Browser.Adapters.AgentBrowser, :extract_content, fn ^session, _opts ->
        {:ok, session, %{content: "# Hello World", format: :markdown}}
      end)

      assert {:ok, ^session, %{content: "# Hello World", format: :markdown}} =
               Jido.Browser.extract_content(session)
    end
  end

  describe "end_session/1" do
    test "delegates to adapter" do
      session = build_session()

      expect(Jido.Browser.Adapters.AgentBrowser, :end_session, fn ^session ->
        :ok
      end)

      assert :ok = Jido.Browser.end_session(session)
    end
  end

  # Helpers

  defp build_session do
    Session.new!(%{
      adapter: Jido.Browser.Adapters.AgentBrowser,
      connection: %{binary: "/usr/local/bin/agent-browser"},
      runtime: %{manager: self()},
      capabilities: %{native_snapshot: true}
    })
  end
end
