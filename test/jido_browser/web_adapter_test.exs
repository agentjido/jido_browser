defmodule Jido.Browser.WebAdapterTest do
  use ExUnit.Case, async: false

  alias Jido.Browser
  alias Jido.Browser.Adapters.Web
  alias Jido.Browser.TestSupport.FakeWebBinary

  describe "explicit binary overrides" do
    test "unpooled sessions honor the explicit binary option" do
      FakeWebBinary.with_binary(:normal, fn binary, _profile_root ->
        with_web_config([binary_path: "/missing/web"], fn ->
          assert {:ok, session} = Web.start_session(profile: "explicit-binary", binary: binary)

          assert {:ok, _session, %{content: "ok:https://example.com", url: "https://example.com"}} =
                   Web.navigate(session, "https://example.com", [])
        end)
      end)
    end

    test "warm pools honor the explicit binary option" do
      FakeWebBinary.with_binary(:normal, fn binary, _profile_root ->
        with_web_config([binary_path: "/missing/web"], fn ->
          pool_name = "web-binary-#{System.unique_integer([:positive])}"

          assert {:ok, pool} =
                   Browser.start_pool(
                     adapter: Web,
                     name: pool_name,
                     size: 1,
                     binary: binary,
                     warmup_url: "https://example.com"
                   )

          on_exit(fn -> Browser.stop_pool(pool) end)

          assert {:ok, session} = Browser.start_session(adapter: Web, pool: pool_name)

          assert {:ok, _session, %{content: "ok:https://example.com", url: "https://example.com"}} =
                   Browser.navigate(session, "https://example.com")

          assert :ok = Browser.end_session(session)
        end)
      end)
    end
  end

  defp with_web_config(config, fun) do
    old_config = Application.get_env(:jido_browser, :web, [])
    Application.put_env(:jido_browser, :web, Keyword.merge(old_config, config))

    try do
      fun.()
    after
      Application.put_env(:jido_browser, :web, old_config)
    end
  end
end
