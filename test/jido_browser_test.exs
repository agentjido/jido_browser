defmodule JidoBrowserTest do
  use ExUnit.Case, async: true
  use Mimic

  alias JidoBrowser.Session

  describe "start_session/1" do
    test "creates a session with default adapter" do
      expect(JidoBrowser.Adapters.Vibium, :start_session, fn opts ->
        Session.new(%{
          adapter: JidoBrowser.Adapters.Vibium,
          connection: %{port: opts[:port] || 9515},
          opts: Map.new(opts)
        })
      end)

      assert {:ok, %Session{adapter: JidoBrowser.Adapters.Vibium}} =
               JidoBrowser.start_session()
    end

    test "accepts custom adapter" do
      expect(JidoBrowser.Adapters.Web, :start_session, fn _opts ->
        Session.new(%{
          adapter: JidoBrowser.Adapters.Web,
          connection: %{profile: "default"}
        })
      end)

      assert {:ok, %Session{adapter: JidoBrowser.Adapters.Web}} =
               JidoBrowser.start_session(adapter: JidoBrowser.Adapters.Web)
    end
  end

  describe "navigate/3" do
    test "delegates to adapter" do
      session = build_session()

      expect(JidoBrowser.Adapters.Vibium, :navigate, fn ^session, url, _opts ->
        {:ok, %{url: url}}
      end)

      assert {:ok, %{url: "https://example.com"}} =
               JidoBrowser.navigate(session, "https://example.com")
    end
  end

  describe "click/3" do
    test "delegates to adapter" do
      session = build_session()

      expect(JidoBrowser.Adapters.Vibium, :click, fn ^session, selector, _opts ->
        {:ok, %{selector: selector}}
      end)

      assert {:ok, %{selector: "button#submit"}} =
               JidoBrowser.click(session, "button#submit")
    end
  end

  describe "type/4" do
    test "delegates to adapter" do
      session = build_session()

      expect(JidoBrowser.Adapters.Vibium, :type, fn ^session, selector, text, _opts ->
        {:ok, %{selector: selector, text: text}}
      end)

      assert {:ok, %{selector: "input#email"}} =
               JidoBrowser.type(session, "input#email", "test@example.com")
    end
  end

  describe "screenshot/2" do
    test "delegates to adapter" do
      session = build_session()
      png_bytes = <<137, 80, 78, 71>>

      expect(JidoBrowser.Adapters.Vibium, :screenshot, fn ^session, _opts ->
        {:ok, %{bytes: png_bytes, mime: "image/png"}}
      end)

      assert {:ok, %{bytes: ^png_bytes, mime: "image/png"}} =
               JidoBrowser.screenshot(session)
    end
  end

  describe "extract_content/2" do
    test "delegates to adapter" do
      session = build_session()

      expect(JidoBrowser.Adapters.Vibium, :extract_content, fn ^session, _opts ->
        {:ok, %{content: "# Hello World", format: :markdown}}
      end)

      assert {:ok, %{content: "# Hello World", format: :markdown}} =
               JidoBrowser.extract_content(session)
    end
  end

  describe "end_session/1" do
    test "delegates to adapter" do
      session = build_session()

      expect(JidoBrowser.Adapters.Vibium, :end_session, fn ^session ->
        :ok
      end)

      assert :ok = JidoBrowser.end_session(session)
    end
  end

  # Helpers

  defp build_session do
    Session.new!(%{
      adapter: JidoBrowser.Adapters.Vibium,
      connection: %{port: 9515}
    })
  end
end
