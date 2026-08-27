defmodule Jido.Browser.PoolDependencyDirectionTest do
  use ExUnit.Case, async: false

  alias Mix.Tasks.Xref

  @agent_browser_adapter "lib/jido_browser/adapters/agent_browser.ex"
  @agent_browser_pool_runtime "lib/jido_browser/agent_browser/pool_runtime.ex"
  @lightpanda_adapter "lib/jido_browser/adapters/lightpanda.ex"
  @lightpanda_pool_runtime "lib/jido_browser/adapters/lightpanda/pool_runtime.ex"
  @target_files [
    @agent_browser_adapter,
    @agent_browser_pool_runtime,
    @lightpanda_adapter,
    @lightpanda_pool_runtime
  ]

  setup_all do
    {:ok, graph: xref_graph()}
  end

  test "all adapter and pool runtime nodes are present in the xref graph", %{graph: graph} do
    assert_target_nodes_present(graph)
  end

  test "target presence guard fails when a target node is removed", %{graph: graph} do
    graph_without_target = Map.delete(graph, @lightpanda_pool_runtime)

    assert_raise ExUnit.AssertionError, ~r/expected xref graph to contain .*lightpanda\/pool_runtime\.ex/, fn ->
      assert_target_nodes_present(graph_without_target)
    end
  end

  test "adapter pool runtimes cannot reach back into their adapters", %{graph: graph} do
    refute dependency_path?(graph, @agent_browser_pool_runtime, @agent_browser_adapter)
    refute dependency_path?(graph, @lightpanda_pool_runtime, @lightpanda_adapter)
  end

  test "the Browser and FetchRich cycle stays assigned to issue 92", %{graph: graph} do
    assert dependency_path?(graph, "lib/jido_browser.ex", "lib/jido_browser/fetch_rich.ex")
    assert dependency_path?(graph, "lib/jido_browser/fetch_rich.ex", "lib/jido_browser.ex")
  end

  defp xref_graph do
    path = Path.join(System.tmp_dir!(), "jido_browser_xref_#{System.unique_integer([:positive])}.dot")
    Mix.Task.reenable("xref")
    Xref.run(["graph", "--format", "dot", "--output", path])

    try do
      path
      |> File.stream!()
      |> Enum.reduce(%{}, fn line, graph ->
        case Regex.run(~r/^\s*"([^"]+)" -> "([^"]+)"/, line) do
          [_, source, sink] ->
            graph
            |> Map.put_new(sink, [])
            |> Map.update(source, [sink], &[sink | &1])

          nil ->
            case Regex.run(~r/^\s*"([^"]+)"\s*$/, line) do
              [_, node] -> Map.put_new(graph, node, [])
              nil -> graph
            end
        end
      end)
    after
      File.rm(path)
    end
  end

  defp dependency_path?(graph, source, sink) do
    dependency_path?(graph, [source], sink, MapSet.new())
  end

  defp assert_target_nodes_present(graph) do
    for target <- @target_files do
      assert Map.has_key?(graph, target), "expected xref graph to contain #{target}"
    end
  end

  defp dependency_path?(_graph, [], _sink, _visited), do: false

  defp dependency_path?(graph, [source | rest], sink, visited) do
    cond do
      source == sink ->
        true

      MapSet.member?(visited, source) ->
        dependency_path?(graph, rest, sink, visited)

      true ->
        dependencies = Map.get(graph, source, [])
        dependency_path?(graph, dependencies ++ rest, sink, MapSet.put(visited, source))
    end
  end
end
