defmodule HordeProTest.Repo.Migrations.InitTables do
  use Ecto.Migration

  def change do
    create table("horde_pro_processes") do
      add(:mfargs, :bytea)
      add(:restart_type, :string)
      add(:shutdown_type, :string)
      add(:shutdown_timeout, :integer)
      add(:child_type, :string)
      add(:lock_id, :integer)
    end
  end
end
