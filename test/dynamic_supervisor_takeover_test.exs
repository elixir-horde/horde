defmodule DynamicSupervisorTakeoverTest do
  use ExUnit.Case, async: false

  setup do
    nodes = LocalCluster.start_nodes("takeover-#{System.unique_integer([:positive])}", 2)

    for n <- nodes do
      :erpc.call(n, Application, :ensure_all_started, [:test_app])
    end

    [nodes: nodes]
  end

  test "a name registered by an evicted-but-alive member is restored on rejoin", %{
    nodes: nodes
  } do
    join(nodes)

    {:ok, pid1} = :erpc.call(hd(nodes), Worker, :start, [:worker1])
    owner = node(pid1)
    assert owner in nodes

    survivor = List.first(nodes -- [owner])
    assert pid1 == await_registered(survivor)

    # the owner is evicted from the cluster but stays alive (a membership blip)
    :erpc.call(survivor, Horde.Cluster, :set_members, [TestReg, [{TestReg, survivor}]])
    :erpc.call(survivor, Horde.Cluster, :set_members, [TestSup, [{TestSup, survivor}]])

    # the name is hidden on the survivor, and the process is untouched on the owner
    assert :undefined == await_lookup(survivor, :undefined)
    assert :erpc.call(owner, Process, :alive?, [pid1])
    assert pid1 == :erpc.call(owner, Horde.Registry, :whereis_name, [{TestReg, :worker1}])

    # the owner rejoins; the name must resolve again without any re-registration
    join([owner, survivor])

    assert pid1 == await_registered(survivor)
    assert pid1 == :erpc.call(owner, Horde.Registry, :whereis_name, [{TestReg, :worker1}])
    assert [pid1] == unique_alive([owner, survivor], owner)
  end

  defp await_lookup(node, expected, attempts \\ 40)
  defp await_lookup(_node, _expected, 0), do: :timeout

  defp await_lookup(node, expected, attempts) do
    case :erpc.call(node, Horde.Registry, :whereis_name, [{TestReg, :worker1}]) do
      ^expected ->
        expected

      _ ->
        Process.sleep(250)
        await_lookup(node, expected, attempts - 1)
    end
  end

  defp join(nodes) do
    reg_members = for n <- nodes, do: {TestReg, n}
    sup_members = for n <- nodes, do: {TestSup, n}

    for n <- nodes do
      :ok = :erpc.call(n, Horde.Cluster, :set_members, [TestReg, reg_members])
      :ok = :erpc.call(n, Horde.Cluster, :set_members, [TestSup, sup_members])
    end
  end

  defp await_registered(node, attempts \\ 80)
  defp await_registered(_node, 0), do: :timeout

  defp await_registered(node, attempts) do
    case :erpc.call(node, Horde.Registry, :whereis_name, [{TestReg, :worker1}]) do
      pid when is_pid(pid) ->
        pid

      _ ->
        Process.sleep(250)
        await_registered(node, attempts - 1)
    end
  end

  defp unique_alive(nodes, alive_check_node) do
    nodes
    |> Enum.flat_map(fn n ->
      :erpc.call(n, Horde.DynamicSupervisor, :which_children, [{TestSup, n}])
    end)
    |> Enum.map(fn {_, pid, _, _} -> pid end)
    |> Enum.uniq()
    |> Enum.filter(fn pid -> :erpc.call(alive_check_node, Process, :alive?, [pid]) end)
  end
end
