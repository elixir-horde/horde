defmodule HordePro.RegistryTest do
  use ExUnit.Case

  alias HordePro.Registry, as: Reg

  test "can register a process" do
    name = :one
    pid = self()

    {:ok, _reg} =
      Reg.start_link(name: name, keys: :unique, partitions: 4, repo: HordeProTest.Repo)

    assert {:ok, _owner_pid} = Reg.register(name, "hello", "here I am")
    assert [{^pid, "here I am"}] = Reg.lookup(name, "hello")
  end
end
