defmodule HordePro.Process do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  schema "horde_pro_processes" do
    field(:mfargs, :binary)
    field(:restart_type, :string)
    field(:shutdown_type, :string)
    field(:shutdown_timeout, :integer)
    field(:child_type, :string)
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
