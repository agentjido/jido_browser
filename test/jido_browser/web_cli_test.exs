defmodule Jido.Browser.WebCLITest do
  use ExUnit.Case, async: false

  alias Jido.Browser.Adapters.Web.CLI
  alias Jido.Browser.TestSupport.FakeWebBinary

  describe "execute/3" do
    test "returns unsupported_action for unsupported commands" do
      assert {:error, :unsupported_action} = CLI.execute("profile", %{"action" => "unknown"}, [])
    end

    test "returns command errors for non-zero exits" do
      FakeWebBinary.with_binary(:nonzero, fn binary, _profile_root ->
        assert {:error, reason} =
                 CLI.execute("profile", %{"action" => "navigate", "url" => "https://example.com"},
                   binary: binary,
                   timeout: 500
                 )

        assert reason =~ "web exited with code 42"
      end)
    end

    test "times out long-running commands" do
      FakeWebBinary.with_binary(:timeout, fn binary, _profile_root ->
        assert {:error, "Command timed out after 25ms"} =
                 CLI.execute("profile", %{"action" => "navigate", "url" => "https://example.com"},
                   binary: binary,
                   timeout: 25
                 )
      end)
    end

    test "wraps missing screenshot files in a read failure tuple" do
      FakeWebBinary.with_binary(:missing_screenshot, fn binary, _profile_root ->
        assert {:error, {:screenshot_read_failed, :enoent}} =
                 CLI.execute(
                   "profile",
                   %{"action" => "screenshot", "format" => "png", "current_url" => "https://example.com"},
                   binary: binary,
                   timeout: 500
                 )
      end)
    end
  end

  describe "profile helpers" do
    test "warm_profile prepares a profile and delete_profile removes it" do
      FakeWebBinary.with_binary(:normal, fn binary, profile_root ->
        assert :ok = CLI.warm_profile("warm-profile", binary: binary, timeout: 500)
        assert File.dir?(Path.join(profile_root, "warm-profile"))
        assert :ok = CLI.delete_profile("warm-profile")
        refute File.exists?(Path.join(profile_root, "warm-profile"))
      end)
    end

    test "warm_profile defaults to a no-network warmup URL" do
      FakeWebBinary.with_binary(:record_url, fn binary, _profile_root ->
        assert :ok = CLI.warm_profile("warm-profile", binary: binary, timeout: 500)
        warmup_url = File.read!(Path.join(Path.dirname(binary), "last-url.txt"))
        uri = URI.parse(warmup_url)

        assert uri.scheme == "http"
        assert uri.host == "127.0.0.1"
        assert uri.path == "/"
      end)
    end
  end
end
