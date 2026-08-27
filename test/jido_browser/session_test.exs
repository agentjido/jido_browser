defmodule Jido.Browser.SessionTest do
  use ExUnit.Case, async: true

  alias Jido.Browser.Session

  test "derives the raw struct contract from the schema" do
    struct_contract = Macro.struct_info!(Session, __ENV__)

    required_keys = MapSet.new(Zoi.Struct.enforce_keys(Session.schema()))

    assert required_keys == MapSet.new([:id, :adapter, :started_at])

    assert Map.new(struct_contract, &{&1.field, &1.default}) == %{
             id: nil,
             adapter: nil,
             connection: nil,
             runtime: nil,
             capabilities: %{},
             started_at: nil,
             opts: %{}
           }
  end

  describe "new/1" do
    test "creates session with required fields" do
      assert {:ok, session} =
               Session.new(%{
                 adapter: Jido.Browser.Adapters.Vibium,
                 connection: %{port: 9515}
               })

      assert session.adapter == Jido.Browser.Adapters.Vibium
      assert session.connection == %{port: 9515}
      assert is_binary(session.id)
      assert %DateTime{} = session.started_at
    end

    test "allows custom id" do
      assert {:ok, session} =
               Session.new(%{
                 id: "custom-id",
                 adapter: Jido.Browser.Adapters.Vibium
               })

      assert session.id == "custom-id"
    end

    test "requires an adapter" do
      assert {:error, [%Zoi.Error{code: :required, path: [:adapter]}]} = Session.new(%{})
    end

    test "uses the session defaults" do
      assert {:ok, session} =
               Session.new(%{
                 adapter: Jido.Browser.Adapters.Vibium
               })

      assert session.connection == nil
      assert session.runtime == nil
      assert session.capabilities == %{}
      assert session.opts == %{}
    end
  end

  describe "new!/1" do
    test "returns session on success" do
      session =
        Session.new!(%{
          adapter: Jido.Browser.Adapters.Vibium,
          connection: %{port: 9515}
        })

      assert %Session{} = session
    end

    test "raises on invalid input" do
      assert_raise ArgumentError, fn ->
        Session.new!(%{})
      end
    end
  end
end
