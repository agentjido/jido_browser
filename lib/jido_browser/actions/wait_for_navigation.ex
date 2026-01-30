defmodule JidoBrowser.Actions.WaitForNavigation do
  @moduledoc """
  Jido Action for waiting for page navigation to complete.

  ## Usage with Jido Agent

      # In your agent's tool list
      tools: [JidoBrowser.Actions.WaitForNavigation]

      # The agent can then call:
      # wait_for_navigation()
      # wait_for_navigation(url: "/dashboard")
      # wait_for_navigation(url: "success", timeout: 5000)

  """

  use Jido.Action,
    name: "browser_wait_for_navigation",
    description: "Wait for page navigation to complete",
    category: "Browser",
    tags: ["browser", "wait", "navigation", "web"],
    vsn: "1.0.0",
    schema: [
      url: [type: :string, doc: "URL pattern to match (substring match)"],
      timeout: [type: :integer, default: 30_000, doc: "Maximum wait time in milliseconds"]
    ]

  alias JidoBrowser.ActionHelpers
  alias JidoBrowser.Error

  @impl true
  def run(params, context) do
    with {:ok, session} <- ActionHelpers.get_session(context) do
      url_pattern = params[:url]
      timeout = params[:timeout] || 30_000

      js = build_wait_js(url_pattern, timeout)

      case JidoBrowser.evaluate(session, js, []) do
        {:ok, updated_session, %{result: %{"url" => url, "elapsed" => elapsed}}} ->
          {:ok, %{status: "success", url: url, elapsed_ms: elapsed, session: updated_session}}

        {:ok, updated_session, %{result: %{"url" => url} = result}} ->
          elapsed = Map.get(result, "elapsed", 0)
          {:ok, %{status: "success", url: url, elapsed_ms: elapsed, session: updated_session}}

        {:error, reason} ->
          {:error, Error.navigation_error("wait_for_navigation", reason)}
      end
    end
  end

  defp build_wait_js(nil, timeout) do
    """
    (function waitForNav(urlPattern, timeout) {
      const start = Date.now();
      const startUrl = window.location.href;
      return new Promise((resolve, reject) => {
        function check() {
          const elapsed = Date.now() - start;
          if (elapsed > timeout) {
            reject(new Error('Navigation timeout'));
            return;
          }
          const currentUrl = window.location.href;
          const changed = currentUrl !== startUrl;
          const matches = !urlPattern || currentUrl.includes(urlPattern);
          if (changed && matches) resolve({url: currentUrl, elapsed: elapsed});
          else setTimeout(check, 100);
        }
        check();
      });
    })(null, #{timeout})
    """
  end

  defp build_wait_js(url_pattern, timeout) do
    escaped_pattern = String.replace(url_pattern, "'", "\\'")

    """
    (function waitForNav(urlPattern, timeout) {
      const start = Date.now();
      const startUrl = window.location.href;
      return new Promise((resolve, reject) => {
        function check() {
          const elapsed = Date.now() - start;
          if (elapsed > timeout) {
            reject(new Error('Navigation timeout'));
            return;
          }
          const currentUrl = window.location.href;
          const changed = currentUrl !== startUrl;
          const matches = !urlPattern || currentUrl.includes(urlPattern);
          if (changed && matches) resolve({url: currentUrl, elapsed: elapsed});
          else setTimeout(check, 100);
        }
        check();
      });
    })('#{escaped_pattern}', #{timeout})
    """
  end
end
