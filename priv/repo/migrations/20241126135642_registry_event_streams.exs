defmodule HordeProTest.Repo.Migrations.RegistryEventStreams do
  use Ecto.Migration

  def change do
    create table("horde_pro_registry_event_streams") do
      add(:registry_id, :string, null: false)
      add(:event_counter, :integer, null: false)
    end

    create(unique_index("horde_pro_registry_event_streams", [:registry_id]))
  end
end
