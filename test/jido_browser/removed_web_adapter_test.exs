defmodule Jido.Browser.RemovedWebAdapterTest do
  use ExUnit.Case, async: true

  alias Jido.Browser.Installer

  test "does not compile the removed Web runtime modules" do
    refute Code.ensure_loaded?(Jido.Browser.Adapters.Web)
    refute Code.ensure_loaded?(Jido.Browser.Adapters.Web.CLI)
    refute Code.ensure_loaded?(Jido.Browser.Adapters.Web.PoolRuntime)
  end

  test "does not expose the removed Web installer target" do
    for function <- [:installed?, :bin_path, :configured_version, :install] do
      assert_raise FunctionClauseError, fn -> apply(Installer, function, [:web]) end
    end
  end
end
