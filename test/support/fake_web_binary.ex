defmodule Jido.Browser.TestSupport.FakeWebBinary do
  @moduledoc false

  @spec with_binary(atom(), (String.t(), String.t() -> result)) :: result when result: var
  def with_binary(mode, fun) when is_atom(mode) and is_function(fun, 2) do
    tmp_dir = Path.join(System.tmp_dir!(), "jido_browser_fake_web_#{System.unique_integer([:positive])}")
    binary = Path.join(tmp_dir, "web")
    profile_root = Path.join(tmp_dir, "profiles")
    old_config = Application.get_env(:jido_browser, :web, [])

    File.mkdir_p!(profile_root)
    File.write!(binary, script(mode))
    File.chmod!(binary, 0o755)
    Application.put_env(:jido_browser, :web, Keyword.put(old_config, :profile_root, profile_root))

    try do
      fun.(binary, profile_root)
    after
      Application.put_env(:jido_browser, :web, old_config)
      File.rm_rf(tmp_dir)
    end
  end

  defp script(mode) do
    """
    #!/bin/sh
    MODE=#{mode}
    PROFILE=""
    if [ "$1" = "--profile" ]; then
      PROFILE="$2"
      shift 2
    fi

    URL="$1"
    shift

    if [ -n "$PROFILE" ]; then
      mkdir -p "$HOME/profiles/$PROFILE"
    fi

    case "$MODE" in
      normal)
        if [ "$1" = "--screenshot" ]; then
          printf 'PNG' > "$2"
        else
          printf 'ok:%s' "$URL"
        fi
        exit 0
        ;;
      nonzero)
        printf 'boom'
        exit 42
        ;;
      timeout)
        sleep 1
        exit 0
        ;;
      missing_screenshot)
        exit 0
        ;;
      record_url)
        SCRIPT_DIR=$(dirname "$0")
        printf '%s' "$URL" > "$SCRIPT_DIR/last-url.txt"
        exit 0
        ;;
    esac
    """
  end
end
