defmodule Jido.Browser.WebPoolTest do
  use ExUnit.Case, async: false

  alias Jido.Browser
  alias Jido.Browser.Adapters.AgentBrowser
  alias Jido.Browser.Adapters.Web
  alias Jido.Browser.Adapters.Web.CLI
  alias Jido.Browser.Pool

  describe "warm web adapter pools" do
    test "start_session uses a warm reserved profile and pooled commands run through the lease" do
      with_web_pool_env(fn ->
        pool_name = unique_pool_name()
        assert {:ok, pool} = Browser.start_pool(adapter: Web, name: pool_name, size: 1)
        on_exit(fn -> Browser.stop_pool(pool) end)

        assert {:ok, session} = Browser.start_session(pool: pool_name)
        assert session.adapter == Web

        assert {:ok, session, %{url: "https://example.com", content: "Markdown for https://example.com"}} =
                 Browser.navigate(session, "https://example.com")

        assert {:ok, _session, %{title: "Test Page"}} = Browser.get_title(session)
        assert :ok = Browser.end_session(session)
      end)
    end

    test "end_session recycles the reserved profile and warms a replacement" do
      with_web_pool_env(fn ->
        pool_name = unique_pool_name()
        assert {:ok, pool} = Browser.start_pool(adapter: Web, name: pool_name, size: 1)
        on_exit(fn -> Browser.stop_pool(pool) end)

        assert {:ok, session_one} = Browser.start_session(adapter: Web, pool: pool_name)
        profile_one = session_one.connection.profile
        profile_one_path = CLI.profile_path(profile_one)
        assert File.dir?(profile_one_path)
        assert :ok = Browser.end_session(session_one)

        assert {:ok, session_two} =
                 Browser.start_session(adapter: Web, pool: pool_name, checkout_timeout: 1_000)

        profile_two = session_two.connection.profile
        refute profile_two == profile_one
        refute File.exists?(profile_one_path)
        assert File.dir?(CLI.profile_path(profile_two))
        assert :ok = Browser.end_session(session_two)
      end)
    end

    test "supervised pool child works with the web adapter" do
      with_web_pool_env(fn ->
        pool_name = "web-supervised-#{System.unique_integer([:positive])}"
        start_supervised!({Pool, adapter: Web, name: pool_name, size: 1})

        assert {:ok, session} = Browser.start_session(adapter: Web, pool: pool_name)
        assert {:ok, session, _} = Browser.navigate(session, "https://example.com")

        assert {:ok, _session, %{content: "Fixture text", format: :text}} =
                 Browser.extract_content(session, format: :text)

        assert :ok = Browser.end_session(session)
      end)
    end

    test "pooled web sessions reject explicit persistent profile state" do
      with_web_pool_env(fn ->
        pool_name = unique_pool_name()

        assert {:error, error} =
                 Browser.start_pool(adapter: Web, name: pool_name, size: 1, profile: "default")

        assert Exception.message(error) =~ "do not support profile"

        assert {:ok, pool} = Browser.start_pool(adapter: Web, name: pool_name, size: 1)
        on_exit(fn -> Browser.stop_pool(pool) end)

        assert {:error, error} =
                 Browser.start_session(adapter: Web, pool: pool_name, profile: "default")

        assert Exception.message(error) =~ "do not support profile"
      end)
    end

    test "start_session rejects an explicit adapter that does not own the pool" do
      with_web_pool_env(fn ->
        pool_name = unique_pool_name()
        assert {:ok, pool} = Browser.start_pool(adapter: Web, name: pool_name, size: 1)
        on_exit(fn -> Browser.stop_pool(pool) end)

        assert {:error, error} =
                 Browser.start_session(adapter: AgentBrowser, pool: pool_name)

        assert Exception.message(error) =~ "belongs to adapter"
        assert Exception.message(error) =~ inspect(Web)
      end)
    end
  end

  defp with_web_pool_env(fun) do
    tmp_dir = Path.join(System.tmp_dir!(), "jido_browser_web_pool_#{System.unique_integer([:positive])}")
    bin_path = Path.join(tmp_dir, "web")
    profile_root = Path.join(tmp_dir, ".web-firefox/profiles")
    old_home = System.get_env("HOME")
    old_config = Application.get_env(:jido_browser, :web, [])

    File.mkdir_p!(tmp_dir)
    File.mkdir_p!(profile_root)
    File.write!(bin_path, fake_web_binary())
    File.chmod!(bin_path, 0o755)

    System.put_env("HOME", tmp_dir)

    Application.put_env(
      :jido_browser,
      :web,
      old_config
      |> Keyword.put(:binary_path, bin_path)
      |> Keyword.put(:profile_root, profile_root)
    )

    try do
      fun.()
    after
      restore_home(old_home)
      Application.put_env(:jido_browser, :web, old_config)
      File.rm_rf(tmp_dir)
    end
  end

  defp restore_home(nil), do: System.delete_env("HOME")
  defp restore_home(home), do: System.put_env("HOME", home)

  defp fake_web_binary do
    """
    #!/bin/sh
    PROFILE=""
    if [ "$1" = "--profile" ]; then
      PROFILE="$2"
      shift 2
    fi

    URL="$1"
    shift

    if [ -n "$PROFILE" ]; then
      mkdir -p "$HOME/.web-firefox/profiles/$PROFILE"
    fi

    case "$1" in
      --screenshot)
        printf 'PNG' > "$2"
        exit 0
        ;;
      --html)
        printf '<html><body><h1>Fixture</h1></body></html>'
        exit 0
        ;;
      --text)
        printf 'Fixture text'
        exit 0
        ;;
      --js)
        SCRIPT="$2"
        if [ "$SCRIPT" = "document.title" ]; then
          printf '"Test Page"'
        elif [ "$SCRIPT" = "window.location.href" ]; then
          printf '"%s"' "$URL"
        else
          printf '{"ok":true}'
        fi
        exit 0
        ;;
      --click)
        printf 'Clicked %s' "$2"
        exit 0
        ;;
      --fill)
        printf 'Filled %s' "$2"
        exit 0
        ;;
      *)
        printf 'Markdown for %s' "$URL"
        exit 0
        ;;
    esac
    """
  end

  defp unique_pool_name do
    "web-pool-#{System.unique_integer([:positive])}"
  end
end
