defmodule Horde.RegistryTest do
  use ExUnit.Case

  alias Horde.Registry, as: Reg

  def reg(name, extra_opts \\ []) do
    registry_id = to_string(Keyword.get(extra_opts, :registry_id, name))

    initial_opts = [
      name: name,
      keys: :unique,
      backend:
        Horde.Adapter.Postgres.RegistryBackend.new(
          repo: HordeTest.Repo,
          registry_id: registry_id
        ),
      partitions: 4
    ]

    opts = Keyword.merge(initial_opts, extra_opts)
    Reg.start_link(opts)
  end

  test "can register a process" do
    name = :one
    pid = self()

    {:ok, _reg} =
      Reg.start_link(
        name: name,
        keys: :unique,
        partitions: 4,
        backend:
          Horde.Adapter.Postgres.RegistryBackend.new(
            repo: HordeTest.Repo,
            registry_id: to_string(name)
          )
      )

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
    # Process.sleep(1000)
    assert [] = Reg.lookup(name, key)
  end

  test "unregisters a dead process" do
    name = :three
    {:ok, _reg} = reg(name)
    test_pid = self()
    key = :rand.uniform(10_000_000_000_000) |> to_string()

    pid =
      spawn(fn ->
        assert {:ok, _owner_pid} = Reg.register(name, key, "here I am")
        send(test_pid, :continue)

        receive do
          :continue -> nil
        end
      end)

    assert_receive :continue
    assert [{^pid, "here I am"}] = Reg.lookup(name, key)
    send(pid, :continue)
    Process.sleep(1000)
    assert [] = Reg.lookup(name, key)
  end

  test "registry catches up on startup" do
    {:ok, _} = reg(:start1, registry_id: :start)

    key = :rand.uniform(10_000_000_000_000) |> to_string()
    {:ok, _pid} = Reg.register(:start1, key, "here I am")

    {:ok, _} = reg(:start2, registry_id: :start)

    pid = self()
    assert [{^pid, "here I am"}] = Reg.lookup(:start1, key)
    assert [{^pid, "here I am"}] = Reg.lookup(:start2, key)
  end

  test "registry clears out registered keys of dead registries" do
    {:ok, reg1} = reg(:clear1, registry_id: :clear)

    key = :rand.uniform(10_000_000_000_000) |> to_string()

    test_pid = self()

    pid =
      spawn(fn ->
        {:ok, _pid} = Reg.register(:clear1, key, "here I am")
        send(test_pid, :continue)

        receive do
          :continue -> nil
        end
      end)

    assert_receive :continue

    {:ok, _} = reg(:clear2, registry_id: :clear)

    assert [{^pid, "here I am"}] = Reg.lookup(:clear1, key)
    assert [{^pid, "here I am"}] = Reg.lookup(:clear2, key)

    Process.unlink(reg1)
    Process.exit(reg1, :kill)
    Process.sleep(2000)
    assert [] = Reg.lookup(:clear2, key)
  end
end
