defmodule HordeTest.Repo.Migrations.ShardChildrenTable do
  use Ecto.Migration

  def change do
    alter table("horde_children") do
      add(:supervisor_id, :string)
    end
  end
end
