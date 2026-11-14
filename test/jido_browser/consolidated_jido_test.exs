defmodule Jido.Browser.ConsolidatedJidoTest do
  use ExUnit.Case, async: false

  alias Jido.Browser.Actions
  alias Jido.Browser.Adapters.Test, as: TestAdapter

  defmodule BrowserAgent do
    use Jido.Agent,
      name: "browser_explicit_route_contract",
      plugins: [{Jido.Browser.Plugin, %{adapter: Jido.Browser.Adapters.Test}}]

    routes do
      route "browser.get_title", Jido.Browser.Actions.GetTitle do
        state(:unchanged)
      end
    end
  end

  test "Exec validates a complete session sequence with the test adapter" do
    assert {:ok, %{session: session}} = Jido.Exec.run(Actions.StartSession, %{adapter: TestAdapter})

    assert {:ok, %{session: navigated, url: "https://example.com"}} =
             Jido.Exec.run(Actions.Navigate, %{url: "https://example.com"}, %{session: session})

    assert {:ok, %{title: title}} = Jido.Exec.run(Actions.GetTitle, %{}, %{session: navigated})
    assert is_binary(title)
    assert {:ok, %{status: "success"}} = Jido.Exec.run(Actions.EndSession, %{}, %{session: navigated})
    assert {:error, %Jido.Error.ValidationError{}} = Jido.Exec.run(Actions.Navigate, %{})
  end

  test "plugin state and explicit routes work without automatic metadata routes" do
    agent = BrowserAgent.instantiate!(id: Jido.Id.uuid7())
    assert agent.state.browser.adapter == TestAdapter
    assert {:ok, session} = TestAdapter.start_session()
    signal = Jido.Signal.new!(%{type: "browser.get_title", source: "/browser/test", data: %{}})
    assert {:ok, next, []} = Jido.Agent.cmd(agent, signal, context: %{session: session})
    assert next.state == agent.state
    assert Enum.map(BrowserAgent.definition().routes, & &1.path) == ["browser.get_title"]
    assert :ok = TestAdapter.end_session(session)
  end
end
