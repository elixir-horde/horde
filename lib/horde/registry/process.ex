defmodule Horde.Registry.Process do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset

  schema "horde_registry_processes" do
    field(:registry_id, :string)
    field(:key, :binary)
    field(:pid, :binary)
    field(:value, :binary)
    field(:is_unique, :boolean)
    field(:lock_id, :integer)
  end

  def changeset(process, params) do
    cast(process, params, [])
  end
end
