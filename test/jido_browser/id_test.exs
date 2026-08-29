defmodule Jido.Browser.IDTest do
  use ExUnit.Case, async: true

  alias Jido.Browser.AgentBrowser.Protocol
  alias Jido.Browser.ID
  alias Jido.Browser.Session
  alias Jido.Browser.WarmPool.Lease

  @uuid7 ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/

  test "generates unique IDs with the Jido UUIDv7 shape" do
    ids = Enum.map(1..100, fn _index -> ID.generate() end)

    assert Enum.all?(ids, &is_binary/1)
    assert Enum.all?(ids, &Regex.match?(@uuid7, &1))
    assert ids |> Enum.uniq() |> length() == length(ids)
  end

  test "uses the shared contract for default session and request IDs" do
    session = Session.new!(%{adapter: Jido.Browser.Adapters.AgentBrowser})
    request_id = Protocol.request_id()

    assert session.id =~ @uuid7
    assert request_id =~ @uuid7
    refute session.id == request_id
  end

  test "uses the shared contract in composite lease child IDs" do
    assert %{id: {Lease, id}} = Lease.child_spec([])
    assert id =~ @uuid7
  end

  test "does not declare Uniq as a direct dependency" do
    dependency_names = Mix.Project.config()[:deps] |> Enum.map(&elem(&1, 0))

    refute :uniq in dependency_names
  end
end
