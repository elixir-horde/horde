defmodule HordePro.LockerTest do
  use ExUnit.Case, async: true

  alias HordePro.Locker
  alias HordeProTest.Repo

  defp locker() do
    {:ok, locker} = Locker.start_link(repo: Repo)
    locker
  end

  test "can acquire a lock" do
    locker1 = locker()
    locker2 = locker()
    assert true == Locker.try_lock(locker1, "hello!")
    assert false == Locker.try_lock(locker2, "hello!")
  end

  test "tracks which locks have been acquired" do
    locker1 = locker()
    assert true == Locker.try_lock(locker1, "lock1")
    assert true == Locker.try_lock(locker1, "lock2")
    assert ["lock2", "lock1"] == Locker.which_locks(locker1)
  end

  test "unlocks when process dies" do
    locker1 = locker()
    locker2 = locker()

    assert true == Locker.try_lock(locker1, "lock1")
    assert false == Locker.try_lock(locker2, "lock1")

    GenServer.stop(locker1)

    assert true == Locker.try_lock(locker2, "lock1")
  end
end
