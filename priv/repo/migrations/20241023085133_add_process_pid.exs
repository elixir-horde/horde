defmodule HordeTest.Repo.Migrations.AddProcessPid do
  use Ecto.Migration

  def change do
    alter table("horde_processes") do
      add(:pid, :bytea)
    end
  end
end
