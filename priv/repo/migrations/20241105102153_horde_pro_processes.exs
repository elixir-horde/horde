defmodule HordeTest.Repo.Migrations.HordeProcesses do
  use Ecto.Migration

  def change do
    create table("horde_registry_processes") do
      add(:registry_id, :string)
      add(:key, :bytea)
      add(:pid, :bytea)
      add(:value, :bytea)
      add(:is_unique, :boolean)
    end

    create(index("horde_registry_processes", [:registry_id, :key]))
    create(index("horde_registry_processes", [:registry_id, :pid]))

    create(
      unique_index("horde_registry_processes", [:registry_id, :key],
        name: "horde_registry_processes_unique_keys_idx",
        where: "is_unique"
      )
    )

    create table("horde_registry_meta") do
      add(:registry_id, :string)
      add(:key, :bytea)
      add(:value, :bytea)
    end

    create(index("horde_registry_meta", [:registry_id, :key]))

    create table("horde_registry_events") do
      add(:registry_id, :string)
      add(:event_counter, :integer)
      add(:event_type, :string)
      add(:event_body, :bytea)
    end

    create(unique_index("horde_registry_events", [:registry_id, :event_counter]))
  end
end
