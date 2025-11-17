defmodule HordeTest.Repo.Migrations.RemoveEventTypeField do
  use Ecto.Migration

  def change do
    alter table("horde_registry_events") do
      remove(:event_type, :string)
    end
  end
end
