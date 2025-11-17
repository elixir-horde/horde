defmodule Horde.Adapter.Postgres.LockerTest do
  use ExUnit.Case, async: true

  alias Horde.Adapter.Postgres.Locker
  alias HordeTest.Repo

  require Horde.Adapter.Postgres.Locker

  defp locker() do
    {:ok, locker} = Locker.start_link(repo: Repo)
    locker
  end

  test "try_lock/2" do
    locker1 = locker()
    locker2 = locker()
    assert true == Locker.try_lock(locker1, 1)
    assert false == Locker.try_lock(locker2, 1)
  end

  test "unlocks when process dies" do
    locker1 = locker()
    locker2 = locker()

    assert true == Locker.try_lock(locker1, 2)
    assert false == Locker.try_lock(locker2, 2)

    Process.flag(:trap_exit, true)
    Process.exit(locker1, :kill)
    assert_receive {:EXIT, ^locker1, :killed}

    Process.sleep(20)

    assert true == Locker.try_lock(locker2, 2)
  end

  test "release/2" do
    locker1 = locker()
    locker2 = locker()

    assert true == Locker.try_lock(locker1, 3)
    assert false == Locker.try_lock(locker2, 3)

    assert true == Locker.release(locker1, 3)

    assert true == Locker.try_lock(locker2, 3)
  end

  test "with_lock/3" do
    locker1 = locker()
    locker2 = locker()

    Locker.with_lock locker1, 4 do
      assert false == Locker.try_lock(locker2, 4)
    end

    assert true == Locker.try_lock(locker2, 4)
  end

  test "with_lock/3 handles exceptions" do
    locker1 = locker()
    locker2 = locker()

    assert_raise RuntimeError, fn ->
      Locker.with_lock locker1, 5 do
        raise "stop here"
      end
    end

    assert true == Locker.try_lock(locker2, 5)
  end

  test "listen / notify" do
    locker1 = locker()
    true = Locker.listen(locker1, "channel2")
    Ecto.Adapters.SQL.query(Repo, ~s(NOTIFY "channel2", 'UPDATE1'), [])
    Ecto.Adapters.SQL.query(Repo, ~s[SELECT pg_notify('channel2', 'UPDATE2')], [])
    Ecto.Adapters.SQL.query(Repo, ~s[SELECT pg_notify($1, 'UPDATE3')], ["channel2"])
    assert_receive {:notice, "channel2", "UPDATE1"}
    assert_receive {:notice, "channel2", "UPDATE2"}
    assert_receive {:notice, "channel2", "UPDATE3"}
  end

  test "listen/notify works when lock has been acquired" do
    locker1 = locker()
    true = Locker.try_lock(locker1, 1100)
    true = Locker.listen(locker1, "channel3")
    Ecto.Adapters.SQL.query(Repo, ~s(NOTIFY "channel3", 'UPDATE1'), [])
    Ecto.Adapters.SQL.query(Repo, ~s[SELECT pg_notify('channel3', 'UPDATE2')], [])
    Ecto.Adapters.SQL.query(Repo, ~s[SELECT pg_notify($1, 'UPDATE3')], ["channel3"])
    assert_receive {:notice, "channel3", "UPDATE1"}
    assert_receive {:notice, "channel3", "UPDATE2"}
    assert_receive {:notice, "channel3", "UPDATE3"}
  end
end
