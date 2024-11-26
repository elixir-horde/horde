defmodule HordeProTest.Repo.Migrations.EventCounterNotNull do
  use Ecto.Migration

  def change do
    alter table("horde_pro_registry_events") do
      modify(:event_counter, :integer, null: false)
    end
  end
end
