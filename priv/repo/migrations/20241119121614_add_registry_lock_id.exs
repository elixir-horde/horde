defmodule HordeTest.Repo.Migrations.AddRegistryLockId do
  use Ecto.Migration

  def change do
    alter table("horde_registry_processes") do
      add(:lock_id, :integer, null: false)
    end
  end
end
