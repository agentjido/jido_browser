defmodule JidoBrowser.Actions.Wait do
  @moduledoc """
  Jido Action for a simple timeout wait.

  ## Usage with Jido Agent

      # In your agent's tool list
      tools: [JidoBrowser.Actions.Wait]

      # The agent can then call:
      # wait(ms: 1000)
      # wait(ms: 500)

  """

  use Jido.Action,
    name: "browser_wait",
    description: "Wait for a specified number of milliseconds",
    category: "Browser",
    tags: ["browser", "wait", "sync", "web"],
    vsn: "1.0.0",
    schema: [
      ms: [type: :integer, required: true, doc: "Milliseconds to wait"]
    ]

  @impl true
  def run(%{ms: ms}, _context) do
    Process.sleep(ms)
    {:ok, %{status: "success", waited_ms: ms}}
  end
end
