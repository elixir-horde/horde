defmodule HordeProTest do
  use ExUnit.Case
  doctest HordePro

  alias HordeProd.DynamicSupervisor, as: Sup

  @connect_opts [
    username: "postgres",
    password: "postgres",
    database: "horde_pro",
    port: "6431"
  ]

  test "starts a child" do
    Sup.start_link(name: :n1, strategy: :one_for_one, connect_opts: @connect_opts)
  end
end
