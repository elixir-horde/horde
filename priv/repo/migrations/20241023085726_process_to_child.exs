defmodule HordeProTest.Repo.Migrations.ProcessToChild do
  use Ecto.Migration

  def change do
    rename(table("horde_pro_processes"), to: table("horde_pro_children"))
  end
end
