defmodule HordePro.DynamicSupervisorTest do
  use ExUnit.Case

  doctest HordePro

  alias HordePro.DynamicSupervisor, as: Sup

  defp child_spec(sup_name) do
    Sup.child_spec(
      strategy: :one_for_one,
      backend:
        HordePro.Adapter.Postgres.DynamicSupervisorBackend.new(
          repo: HordeProTest.Repo,
          supervisor_id: sup_name
        )
    )
  end

  defp sup(name) do
    {:ok, supervisor} =
      Sup.start_link(
        strategy: :one_for_one,
        backend:
          HordePro.Adapter.Postgres.DynamicSupervisorBackend.new(
            repo: HordeProTest.Repo,
            supervisor_id: name
          )
      )

    supervisor
  end

  test "starts a child" do
    sup = sup("n1")

    test_pid = self()

    {:ok, _pid} =
      Sup.start_child(
        sup,
        {Task,
         fn ->
           send(test_pid, :test_message)
           Process.sleep(1000)
         end}
      )

    assert_receive :test_message
  end

  test "handles termination" do
    Process.flag(:trap_exit, true)

    sup1 = sup("n2")
    _sup2 = sup("n2")
    test_pid = self()

    child_spec =
      Task.child_spec(fn ->
        send(test_pid, {self(), :test_message2})
        Process.sleep(1000)
      end)
      |> Map.put(:restart, :transient)

    {:ok, child_pid} = Sup.start_child(sup1, child_spec)

    # to make this work, I need to have the ability to shard multiple supervisors in the same table

    assert_receive({^child_pid, :test_message2})

    Process.exit(sup1, :kill)

    assert_receive({_child_pid, :test_message2}, 10000)
  end

  test "can be used with PartitionSupervisor" do
    PartitionSupervisor.start_link(
      name: MyPartitionSupervisor,
      child_spec: child_spec("hello")
    )

    test_pid = self()

    {:ok, _child_pid} =
      Sup.start_child(
        {:via, PartitionSupervisor, {MyPartitionSupervisor, :rand.uniform(1000)}},
        {Task,
         fn ->
           send(test_pid, :got_ya!)
           Process.sleep(1000)
         end}
      )

    assert_receive :got_ya!
  end
end
