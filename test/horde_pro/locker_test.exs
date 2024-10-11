defmodule HordePro.LockerTest do
  use ExUnit.Case, async: true

  alias HordePro.Locker
  alias HordeProTest.Repo

  require Locker

  defp locker() do
    {:ok, locker} = Locker.start_link(repo: Repo)
    locker
  end

  test "try_lock/2" do
    locker1 = locker()
    locker2 = locker()
    assert true == Locker.try_lock(locker1, "hello!")
    assert false == Locker.try_lock(locker2, "hello!")
  end

  test "unlocks when process dies" do
    locker1 = locker()
    locker2 = locker()

    assert true == Locker.try_lock(locker1, "lock1")
    assert false == Locker.try_lock(locker2, "lock1")

    Process.flag(:trap_exit, true)
    Process.exit(locker1, :kill)
    assert_receive {:EXIT, ^locker1, :killed}

    Process.sleep(20)

    assert true == Locker.try_lock(locker2, "lock1")
  end

  test "release/2" do
    locker1 = locker()
    locker2 = locker()

    assert true == Locker.try_lock(locker1, "lock2")
    assert false == Locker.try_lock(locker2, "lock2")

    assert true == Locker.release(locker1, "lock2")

    assert true == Locker.try_lock(locker2, "lock2")
  end

  test "with_lock/3" do
    locker1 = locker()
    locker2 = locker()

    Locker.with_lock locker1, "lock3" do
      assert false == Locker.try_lock(locker2, "lock3")
    end

    assert true == Locker.try_lock(locker2, "lock3")
  end

  test "with_lock/3 handles exceptions" do
    locker1 = locker()
    locker2 = locker()

    assert_raise RuntimeError, fn ->
      Locker.with_lock locker1, "lock3" do
        raise "stop here"
      end
    end

    assert true == Locker.try_lock(locker2, "lock3")
  end
end
