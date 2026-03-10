defmodule Jido.BrowserTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Jido.Browser.Session

  describe "start_session/1" do
    test "creates a session with default adapter" do
      expect(Jido.Browser.Adapters.Vibium, :start_session, fn opts ->
        Session.new(%{
          adapter: Jido.Browser.Adapters.Vibium,
          connection: %{port: opts[:port] || 9515},
          opts: Map.new(opts)
        })
      end)

      # Mock returns bare session, adapter wraps with {:ok, ...}
      assert {:ok, %Session{adapter: Jido.Browser.Adapters.Vibium}} =
               Jido.Browser.start_session(adapter: Jido.Browser.Adapters.Vibium)
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

  describe "navigate/3" do
    test "delegates to adapter" do
      session = build_session()

      expect(Jido.Browser.Adapters.Vibium, :navigate, fn ^session, url, _opts ->
        {:ok, %{url: url}}
      end)

      assert {:ok, %{url: "https://example.com"}} =
               Jido.Browser.navigate(session, "https://example.com")
    end
  end

  describe "click/3" do
    test "delegates to adapter" do
      session = build_session()

      expect(Jido.Browser.Adapters.Vibium, :click, fn ^session, selector, _opts ->
        {:ok, %{selector: selector}}
      end)

      assert {:ok, %{selector: "button#submit"}} =
               Jido.Browser.click(session, "button#submit")
    end
  end

  describe "type/4" do
    test "delegates to adapter" do
      session = build_session()

      expect(Jido.Browser.Adapters.Vibium, :type, fn ^session, selector, text, _opts ->
        {:ok, %{selector: selector, text: text}}
      end)

      assert {:ok, %{selector: "input#email"}} =
               Jido.Browser.type(session, "input#email", "test@example.com")
    end
  end

  describe "screenshot/2" do
    test "delegates to adapter" do
      session = build_session()
      png_bytes = <<137, 80, 78, 71>>

      expect(Jido.Browser.Adapters.Vibium, :screenshot, fn ^session, _opts ->
        {:ok, %{bytes: png_bytes, mime: "image/png"}}
      end)

      assert {:ok, %{bytes: ^png_bytes, mime: "image/png"}} =
               Jido.Browser.screenshot(session)
    end
  end

  describe "extract_content/2" do
    test "delegates to adapter" do
      session = build_session()

      expect(Jido.Browser.Adapters.Vibium, :extract_content, fn ^session, _opts ->
        {:ok, %{content: "# Hello World", format: :markdown}}
      end)

      assert {:ok, %{content: "# Hello World", format: :markdown}} =
               Jido.Browser.extract_content(session)
    end
  end

  describe "end_session/1" do
    test "delegates to adapter" do
      session = build_session()

      expect(Jido.Browser.Adapters.Vibium, :end_session, fn ^session ->
        :ok
      end)

      assert :ok = Jido.Browser.end_session(session)
    end
  end

  # Helpers

  defp build_session do
    Session.new!(%{
      adapter: Jido.Browser.Adapters.Vibium,
      connection: %{port: 9515}
    })
  end
end
