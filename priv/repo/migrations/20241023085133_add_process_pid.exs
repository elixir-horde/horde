defmodule HordeProTest.Repo.Migrations.AddProcessPid do
  use Ecto.Migration

  def change do
    alter table("horde_pro_processes") do
      add(:pid, :bytea)
    end
  end
end
