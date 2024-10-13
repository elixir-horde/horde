defmodule HordeProTest.Repo.Migrations.FixProcessesLockId do
  use Ecto.Migration

  def change do
    alter table("horde_pro_processes") do
      add(:modules, :bytea)
    end
  end
end
