defmodule HordePro.LockerTest do
  use ExUnit.Case, async: true

  alias HordePro.Locker
  alias HordeProTest.Repo

  test "can acquire a lock" do
    {:ok, locker} = Locker.start_link(repo: Repo)
    {:ok, locker2} = Locker.start_link(repo: Repo)
    assert true == Locker.try_lock(locker, "hello!")
    assert false == Locker.try_lock(locker2, "hello!")
  end
end
