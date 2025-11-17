defmodule HordeTest.Repo.Migrations.ProcessToChild do
  use Ecto.Migration

  def change do
    rename(table("horde_processes"), to: table("horde_children"))
  end
end
