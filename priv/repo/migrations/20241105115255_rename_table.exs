defmodule HordeProTest.Repo.Migrations.RenameTable do
  use Ecto.Migration

  def change do
    rename(table("horde_pro_children"), to: table("horde_pro_dynamic_supervisor_children"))
  end
end
