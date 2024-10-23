defmodule HordeProTest do
  use ExUnit.Case

  doctest HordePro

  alias HordePro.DynamicSupervisor, as: Sup

  defp sup(name) do
    {:ok, supervisor} =
      Sup.start_link(
        name: name,
        strategy: :one_for_one,
        backend: HordePro.Adapter.Postgres.SupervisorBackend.new(repo: HordeProTest.Repo)
      )

    supervisor
  end

  test "starts a child" do
    sup = sup(:n1)

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

    sup1 = sup(:n2) |> IO.inspect(label: "SUPn2")
    _sup2 = sup(:n3) |> IO.inspect(label: "SUPn3")
    test_pid = self()

    {:ok, child_pid} =
      Sup.start_child(
        sup1,
        {Task,
         fn ->
           IO.inspect("TASK STARTED")
           send(test_pid, {self(), :test_message2})
           Process.sleep(1000)
         end}
      )

    # to make this work, I need to have the ability to shard multiple supervisors in the same table

    assert_receive({^child_pid, :test_message2})

    Process.exit(sup1, :kill)

    assert_receive({_other_pid, :test_message2}, 3000)
  end
end
