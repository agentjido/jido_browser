defmodule JidoBrowser.CompositeActionsAndInstallerTest do
  use ExUnit.Case, async: false
  use Mimic

  alias JidoBrowser.Actions.ReadPage
  alias JidoBrowser.Actions.SearchWeb
  alias JidoBrowser.Actions.SnapshotUrl
  alias JidoBrowser.Installer
  alias JidoBrowser.Session

  setup :set_mimic_global

  setup_all do
    Mimic.copy(Req)
    :ok
  end

  setup do
    session =
      Session.new!(%{
        adapter: JidoBrowser.Adapters.Web,
        connection: %{profile: "default", current_url: nil}
      })

    {:ok, session: session}
  end

  describe "ReadPage.run/2" do
    test "returns content and closes session on success", %{session: session} do
      expect(JidoBrowser, :start_session, fn opts ->
        assert opts == [adapter: JidoBrowser.Adapters.Web]
        {:ok, session}
      end)

      expect(JidoBrowser, :navigate, fn ^session, "https://example.com" ->
        {:ok, session, %{url: "https://example.com"}}
      end)

      expect(JidoBrowser, :extract_content, fn ^session, opts ->
        assert opts[:selector] == "article"
        assert opts[:format] == :text
        {:ok, session, %{content: "Example body"}}
      end)

      expect(JidoBrowser, :end_session, fn ^session -> :ok end)

      assert {:ok, result} =
               ReadPage.run(
                 %{url: "https://example.com", selector: "article", format: :text},
                 %{}
               )

      assert result.url == "https://example.com"
      assert result.content == "Example body"
      assert result.format == :text
    end

    test "returns wrapped error and closes session when navigation fails", %{session: session} do
      expect(JidoBrowser, :start_session, fn [adapter: JidoBrowser.Adapters.Web] -> {:ok, session} end)

      expect(JidoBrowser, :navigate, fn ^session, "https://example.com" ->
        {:error, :navigation_failed}
      end)

      expect(JidoBrowser, :end_session, fn ^session -> :ok end)

      assert {:error, message} = ReadPage.run(%{url: "https://example.com"}, %{})
      assert message =~ "Failed to read page"
      assert message =~ ":navigation_failed"
    end
  end

  describe "SnapshotUrl.run/2" do
    test "returns rich snapshot when evaluate returns structured data", %{session: session} do
      expect(JidoBrowser, :start_session, fn [adapter: JidoBrowser.Adapters.Web] -> {:ok, session} end)

      expect(JidoBrowser, :navigate, fn ^session, "https://example.com" ->
        {:ok, session, %{url: "https://example.com"}}
      end)

      expect(JidoBrowser, :evaluate, fn ^session, script, [] ->
        assert script =~ "function snapshot"

        {:ok, session, %{result: %{"url" => "https://example.com", "title" => "Example Domain", "content" => "Hello"}}}
      end)

      expect(JidoBrowser, :end_session, fn ^session -> :ok end)

      assert {:ok, result} = SnapshotUrl.run(%{url: "https://example.com"}, %{})
      assert result[:status] == "success"
      assert result["title"] == "Example Domain"
    end

    test "falls back to extract_content when evaluate does not return JSON", %{session: session} do
      expect(JidoBrowser, :start_session, fn [adapter: JidoBrowser.Adapters.Web] -> {:ok, session} end)

      expect(JidoBrowser, :navigate, fn ^session, "https://example.com" ->
        {:ok, session, %{url: "https://example.com"}}
      end)

      expect(JidoBrowser, :evaluate, fn ^session, _script, [] ->
        {:ok, session, %{result: "not-json"}}
      end)

      expect(JidoBrowser, :extract_content, fn ^session, opts ->
        assert opts[:selector] == "main"
        assert opts[:format] == :markdown
        {:ok, session, %{content: "abcdefghijklmnopqrstuvwxyz"}}
      end)

      expect(JidoBrowser, :end_session, fn ^session -> :ok end)

      assert {:ok, result} =
               SnapshotUrl.run(
                 %{url: "https://example.com", selector: "main", max_content_length: 8},
                 %{}
               )

      assert result[:status] == "success"
      assert result[:fallback] == true
      assert result[:content] == "abcdefgh"
    end
  end

  describe "SearchWeb.run/2" do
    test "returns parsed search results" do
      with_app_env(:jido_browser, :brave_api_key, "test-key", fn ->
        expect(Req, :get, fn url, opts ->
          assert url == "https://api.search.brave.com/res/v1/web/search"
          assert {"X-Subscription-Token", "test-key"} in opts[:headers]
          assert opts[:params][:q] == "elixir language"
          assert opts[:params][:count] == 20

          {:ok,
           %Req.Response{
             status: 200,
             body: %{
               "web" => %{
                 "results" => [
                   %{
                     "title" => "Elixir",
                     "url" => "https://elixir-lang.org",
                     "description" => "Elixir language"
                   }
                 ]
               }
             }
           }}
        end)

        assert {:ok, result} = SearchWeb.run(%{query: "elixir language", max_results: 50}, %{})
        assert result.count == 1
        assert hd(result.results).title == "Elixir"
        assert hd(result.results).rank == 1
      end)
    end

    test "returns authentication error on 401 response" do
      with_app_env(:jido_browser, :brave_api_key, "bad-key", fn ->
        expect(Req, :get, fn _url, _opts ->
          {:ok, %Req.Response{status: 401, body: %{}}}
        end)

        assert {:error, "Brave Search API: invalid API key"} =
                 SearchWeb.run(%{query: "elixir"}, %{})
      end)
    end

    test "returns clear error when api key is missing" do
      with_app_env(:jido_browser, :brave_api_key, nil, fn ->
        with_system_env("BRAVE_SEARCH_API_KEY", nil, fn ->
          assert {:error, message} = SearchWeb.run(%{query: "elixir"}, %{})
          assert message =~ "Brave Search API key not configured"
        end)
      end)
    end
  end

  describe "Installer" do
    test "target returns a supported platform atom" do
      assert Installer.target() in [
               :darwin_arm64,
               :darwin_amd64,
               :linux_amd64,
               :linux_arm64,
               :windows_amd64
             ]
    end

    test "default_install_path honors configured :path" do
      path = Path.join(System.tmp_dir!(), "jido_browser_custom_path")

      with_app_env(:jido_browser, :path, path, fn ->
        assert Installer.default_install_path() == Path.expand(path)
      end)
    end

    test "configured_version returns defaults and overrides" do
      with_app_env(:jido_browser, :vibium_version, nil, fn ->
        assert Installer.configured_version(:vibium) == "1.0.0"
      end)

      with_app_env(:jido_browser, :vibium_version, "9.9.9", fn ->
        assert Installer.configured_version(:vibium) == "9.9.9"
      end)

      with_app_env(:jido_browser, :web_version, nil, fn ->
        assert Installer.configured_version(:web) == "main"
      end)

      with_app_env(:jido_browser, :web_version, "stable", fn ->
        assert Installer.configured_version(:web) == "stable"
      end)
    end

    test "bin_path/installed? use configured web path when present" do
      path = Path.join(System.tmp_dir!(), "jido_browser_test_web_#{System.unique_integer([:positive])}")
      File.write!(path, "web")
      File.chmod!(path, 0o755)

      try do
        with_app_env(:jido_browser, :web, [binary_path: path], fn ->
          assert Installer.bin_path(:web) == path
          assert Installer.installed?(:web)
        end)
      after
        File.rm(path)
      end
    end

    test "bin_path/installed? use configured vibium path when present" do
      path =
        Path.join(System.tmp_dir!(), "jido_browser_test_clicker_#{System.unique_integer([:positive])}")

      File.write!(path, "clicker")
      File.chmod!(path, 0o755)

      try do
        with_app_env(:jido_browser, :vibium, [binary_path: path], fn ->
          assert Installer.bin_path(:vibium) == path
          assert Installer.installed?(:vibium)
        end)
      after
        File.rm(path)
      end
    end
  end

  defp with_app_env(app, key, value, fun) do
    original = Application.get_env(app, key, :__missing__)

    if is_nil(value) do
      Application.delete_env(app, key)
    else
      Application.put_env(app, key, value)
    end

    try do
      fun.()
    after
      if original == :__missing__ do
        Application.delete_env(app, key)
      else
        Application.put_env(app, key, original)
      end
    end
  end

  defp with_system_env(key, value, fun) do
    original = System.get_env(key)

    if is_nil(value) do
      System.delete_env(key)
    else
      System.put_env(key, value)
    end

    try do
      fun.()
    after
      if is_nil(original) do
        System.delete_env(key)
      else
        System.put_env(key, original)
      end
    end
  end
end
