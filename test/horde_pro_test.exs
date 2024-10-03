defmodule HordeProTest do
  use ExUnit.Case
  doctest HordePro

  test "greets the world" do
    assert HordePro.hello() == :world
  end
end
