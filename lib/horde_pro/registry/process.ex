defmodule HordePro.Registry.Process do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset

  schema "horde_pro_registry_processes" do
    field(:registry_id, :string)
    field(:key, :binary)
    field(:pid, :binary)
    field(:value, :binary)
    field(:is_unique, :boolean)
  end

  def changeset(process, params) do
    cast(process, params, [])
  end
end
