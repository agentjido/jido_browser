defmodule Jido.Browser.RemovedBrowseyTest do
  use ExUnit.Case, async: true

  test "does not include Browsey modules or vendored assets" do
    refute Code.ensure_loaded?(Jido.Browser.WebFetch.Backends.Browsey)
    refute Code.ensure_loaded?(Jido.Browser.Vendor.BrowseyHttp)
    refute File.exists?(Path.expand("../../vendor/browsey_http", __DIR__))
    refute File.exists?(Path.expand("../../priv/vendor/browsey_http", __DIR__))
  end

  test "does not declare dependencies used only by Browsey" do
    dependency_names = Mix.Project.config()[:deps] |> Enum.map(&elem(&1, 0))

    refute :domainatrex in dependency_names
    refute :typed_struct in dependency_names
  end
end
