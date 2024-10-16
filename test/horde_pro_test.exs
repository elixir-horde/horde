defmodule HordeProTest do
  use ExUnit.Case

  doctest HordePro

  alias HordePro.DynamicSupervisor, as: Sup

  test "starts a child" do
    {:ok, sup} = Sup.start_link(name: :n1, strategy: :one_for_one, repo: HordeProTest.Repo)
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
  end
end
