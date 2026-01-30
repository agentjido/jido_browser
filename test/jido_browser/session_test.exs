defmodule JidoBrowser.SessionTest do
  use ExUnit.Case, async: true

  alias JidoBrowser.Session

  describe "new/1" do
    test "creates session with required fields" do
      assert {:ok, session} =
               Session.new(%{
                 adapter: JidoBrowser.Adapters.Vibium,
                 connection: %{port: 9515}
               })

      assert session.adapter == JidoBrowser.Adapters.Vibium
      assert session.connection == %{port: 9515}
      assert is_binary(session.id)
      assert %DateTime{} = session.started_at
    end

    test "allows custom id" do
      assert {:ok, session} =
               Session.new(%{
                 id: "custom-id",
                 adapter: JidoBrowser.Adapters.Vibium
               })

      assert session.id == "custom-id"
    end

    test "defaults opts to empty map" do
      assert {:ok, session} =
               Session.new(%{
                 adapter: JidoBrowser.Adapters.Vibium
               })

      assert session.opts == %{}
    end
  end

  describe "new!/1" do
    test "returns session on success" do
      session =
        Session.new!(%{
          adapter: JidoBrowser.Adapters.Vibium,
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
