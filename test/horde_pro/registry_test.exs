defmodule HordePro.RegistryTest do
  use ExUnit.Case

  alias HordePro.Registry, as: Reg

  def reg(name, extra_opts \\ []) do
    initial_opts = [name: name, keys: :unique, repo: HordeProTest.Repo, partitions: 4]
    opts = Keyword.merge(initial_opts, extra_opts)
    Reg.start_link(opts)
  end

  test "can register a process" do
    name = :one
    pid = self()

    {:ok, _reg} =
      Reg.start_link(name: name, keys: :unique, partitions: 4, repo: HordeProTest.Repo)

    key = :rand.uniform(10_000_000_000_000) |> to_string()
    assert {:ok, _owner_pid} = Reg.register(name, key, "here I am")
    assert [{^pid, "here I am"}] = Reg.lookup(name, key)
  end

  test "can unregister a process" do
    name = :two
    pid = self()

    {:ok, _reg} = reg(name)

    key = :rand.uniform(10_000_000_000_000) |> to_string()
    assert {:ok, _owner_pid} = Reg.register(name, key, "here I am")
    assert [{^pid, "here I am"}] = Reg.lookup(name, key)
    assert :ok = Reg.unregister(name, key)
    assert [] = Reg.lookup(name, key)
  end

  test "unregisters a dead process" do
    name = :three
    {:ok, _reg} = reg(name)
    test_pid = self()
    key = :rand.uniform(10_000_000_000_000) |> to_string()

    pid =
      spawn(fn ->
        pid = self()
        assert {:ok, _owner_pid} = Reg.register(name, key, "here I am")
        send(test_pid, :continue)

        receive do
          :continue -> nil
        end
      end)

    assert_receive :continue
    assert [{^pid, "here I am"}] = Reg.lookup(name, key)
    send(pid, :continue)
    Process.sleep(100)
    assert [] = Reg.lookup(name, key)
  end
end
