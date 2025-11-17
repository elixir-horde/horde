defmodule Horde.Registry.Event do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset

  schema "horde_registry_events" do
    field(:registry_id, :string)
    field(:event_counter, :integer)
    field(:event_body, :binary)
  end

  def changeset(event, params) do
    cast(event, params, [:registry_id, :event_counter, :event_body])
  end
end
