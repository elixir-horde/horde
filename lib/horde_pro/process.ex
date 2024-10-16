defmodule HordePro.Process do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  schema "horde_pro_processes" do
    field(:mfargs, :binary)
    field(:restart_type, Ecto.Enum, values: [:permanent, :transient, :temporary])
    field(:shutdown_type, Ecto.Enum, values: [:infinity, :timeout])
    field(:shutdown_timeout, :integer)
    field(:child_type, Ecto.Enum, values: [:worker, :supervisor])
    field(:lock_id, :integer)
  end

  def changeset(process, params) do
    cast(process, params, [
      :mfargs,
      :restart_type,
      :shutdown_type,
      :shutdown_timeout,
      :child_type,
      :lock_id
    ])
    |> validate_required([
      :mfargs,
      :restart_type,
      :shutdown_type,
      :shutdown_timeout,
      :child_type,
      :lock_id
    ])
  end
end
