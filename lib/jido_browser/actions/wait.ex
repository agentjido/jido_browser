defmodule Jido.Browser.Actions.Wait do
  @moduledoc """
  Jido Action for a simple timeout wait.

  ## Usage with Jido Agent

      # In your agent's tool list
      tools: [Jido.Browser.Actions.Wait]

      # The agent can then call:
      # wait(ms: 1000)
      # wait(ms: 500)

  """

  use Jido.Browser.Action,
    name: "browser_wait",
    description: "Wait for a specified number of milliseconds",
    schema: Zoi.object(%{ms: Zoi.integer(description: "Milliseconds to wait")})

  @impl true
  def run(%{ms: ms}, _context) do
    Process.sleep(ms)
    {:ok, %{status: "success", waited_ms: ms}}
  end
end
