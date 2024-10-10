defmodule HordePro.LockerTest do
  use ExUnit.Case, async: true

  alias HordePro.Locker
  alias HordeProTest.Repo

  test "locker" do
    Locker.start_link(repo: Repo)
  end
end
