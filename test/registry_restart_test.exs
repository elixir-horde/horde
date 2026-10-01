defmodule RegistryRestartTest do
  use ExUnit.Case, async: false

  test "a stale entry left by a dead node must not kill a fresh registration" do
    nodes = start_nodes(3)
    [owner, survivor, fresh] = nodes

    join_reg([owner, survivor])

    # the owner registers a name; the survivor replicates it
    {:ok, pid_old} = :erpc.call(owner, Worker, :start, [:key])
    assert node(pid_old) == owner
    assert [{^pid_old, nil}] = await_lookup(survivor, [{pid_old, nil}])

    # the owner is gone for good: the name is hidden on the survivor,
    # but the raw entry is retained
    LocalCluster.stop_nodes([owner])
    assert [] = await_lookup(survivor, [])
    assert [^pid_old] = select_pids(survivor)

    # in the meantime a fresh node registers the same name on its own
    {:ok, pid_new} = :erpc.call(fresh, Worker, :start, [:key])
    assert node(pid_new) == fresh
    assert [{^pid_new, nil}] = await_lookup(fresh, [{pid_new, nil}])

    # when the fresh node joins, the stale entry arrives: give it time to
    # kill and (without the fix) restart before asserting, so a regression
    # fails on the holder identity instead of racing past
    join_reg([survivor, fresh])
    Process.sleep(1000)

    assert :erpc.call(fresh, Process, :alive?, [pid_new])
    assert [{^pid_new, nil}] = await_lookup(fresh, [{pid_new, nil}])
  end

  test "a stale dead entry with a larger monotonic timestamp does not block a live re-registration" do
    # Start writer + reader early so their monotonic clocks age; start the
    # fresh writer late so its clock is ~0. This forces LWW inversion
    # (T_old > T_new) as after a VM restart with the same logical writer.
    early = start_nodes(2)
    [owner, survivor] = early
    join_reg([owner, survivor])
    Process.sleep(4_000)

    {:ok, pid_old} = :erpc.call(owner, Worker, :start, [:key])
    assert node(pid_old) == owner
    assert [{^pid_old, nil}] = await_lookup(survivor, [{pid_old, nil}])
    ts_old = timestamp_for(survivor, pid_old)

    LocalCluster.stop_nodes([owner])
    assert [] = await_lookup(survivor, [])
    assert [^pid_old] = select_pids(survivor)

    [fresh] = start_nodes(1)
    {:ok, pid_new} = :erpc.call(fresh, Worker, :start, [:key])
    assert node(pid_new) == fresh
    assert [{^pid_new, nil}] = await_lookup(fresh, [{pid_new, nil}])
    ts_new = timestamp_for(fresh, pid_new)

    assert is_integer(ts_old) and is_integer(ts_new)
    assert ts_old > ts_new, "expected inversion old(#{ts_old}) > new(#{ts_new})"

    join_reg([survivor, fresh])
    Process.sleep(2_000)

    assert :erpc.call(fresh, Process, :alive?, [pid_new])
    assert [{^pid_new, nil}] = :erpc.call(fresh, Horde.Registry, :lookup, [TestReg, :key])
    assert [{^pid_new, nil}] = await_lookup(survivor, [{pid_new, nil}])
    assert [^pid_new] = select_pids(survivor)
  end

  defp start_nodes(count) do
    nodes = LocalCluster.start_nodes("restart-#{System.unique_integer([:positive])}", count)

    for n <- nodes do
      :erpc.call(n, Application, :ensure_all_started, [:test_app])
      # each supervisor stays isolated (sole member) so starts land locally
      :ok = :erpc.call(n, Horde.Cluster, :set_members, [TestSup, [{TestSup, n}]])
    end

    nodes
  end

  defp await_lookup(node, expected, attempts \\ 40)
  defp await_lookup(_node, _expected, 0), do: :timeout

  defp await_lookup(node, expected, attempts) do
    case :erpc.call(node, Horde.Registry, :lookup, [TestReg, :key]) do
      ^expected ->
        expected

      _ ->
        Process.sleep(250)
        await_lookup(node, expected, attempts - 1)
    end
  end

  defp select_pids(node) do
    :erpc.call(node, Horde.Registry, :select, [TestReg, [{{:key, :"$1", :_}, [], [:"$1"]}]])
  end

  defp timestamp_for(node, pid) do
    raw = :erpc.call(node, :sys, :get_state, [TestReg.Crdt])
    entries = raw.crdt_state.value |> Map.get({:key, :key}, %{})

    Enum.find_value(entries, fn {{{_member, entry_pid, _val}, ts}, _dots} ->
      if entry_pid == pid, do: ts, else: nil
    end)
  end

  defp join_reg(nodes) do
    reg_members = for n <- nodes, do: {TestReg, n}

    for n <- nodes do
      :ok = :erpc.call(n, Horde.Cluster, :set_members, [TestReg, reg_members])
    end
  end
end
