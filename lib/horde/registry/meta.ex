defmodule Horde.Registry.Meta do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset

  schema "horde_registry_meta" do
    field(:registry_id, :string)
    field(:key, :binary)
    field(:value, :binary)
  end

  def changeset(meta, params) do
    cast(meta, params, [])
  end
end
