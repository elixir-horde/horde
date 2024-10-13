defmodule HordeProTest do
  use ExUnit.Case

  doctest HordePro

  alias HordePro.DynamicSupervisor, as: Sup

  test "starts a child" do
    {:ok, sup} = Sup.start_link(name: :n1, strategy: :one_for_one, repo: HordeProTest.Repo)
    {:ok, pid} = Sup.start_child(sup, {Task, fn -> Process.sleep(1000) end})
  end
end
