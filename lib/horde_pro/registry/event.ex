defmodule HordePro.Registry.Event do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset

  schema "horde_pro_registry_events" do
    field(:registry_id, :string)
    field(:event_counter, :integer)
    field(:event_type, :string)
    field(:event_body, :binary)
  end

  def changeset(event, params) do
    cast(event, params, [])
  end
end
