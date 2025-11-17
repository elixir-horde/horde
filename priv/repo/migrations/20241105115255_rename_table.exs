defmodule HordeTest.Repo.Migrations.RenameTable do
  use Ecto.Migration

  def change do
    rename(table("horde_children"), to: table("horde_dynamic_supervisor_children"))
  end
end
