defmodule HordeTest.Repo.Migrations.FixProcessesLockId do
  use Ecto.Migration

  def change do
    alter table("horde_processes") do
      add(:modules, :bytea)
    end
  end
end
