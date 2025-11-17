defmodule Horde.DynamicSupervisorChild do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  schema "horde_dynamic_supervisor_children" do
    field(:supervisor_id, :string)
    field(:mfargs, :binary)
    field(:pid, :binary)
    field(:restart_type, Ecto.Enum, values: [:permanent, :transient, :temporary])
    field(:shutdown_type, Ecto.Enum, values: [:infinity, :timeout])
    field(:shutdown_timeout, :integer)
    field(:child_type, Ecto.Enum, values: [:worker, :supervisor])
    field(:modules, :binary)
    field(:lock_id, :integer)
  end

  def changeset(process, params) do
    cast(process, params, [
      :supervisor_id,
      :mfargs,
      :pid,
      :restart_type,
      :shutdown_type,
      :shutdown_timeout,
      :child_type,
      :modules,
      :lock_id
    ])
    |> validate_required([
      :supervisor_id,
      :mfargs,
      :pid,
      :restart_type,
      :shutdown_type,
      :shutdown_timeout,
      :child_type,
      :modules,
      :lock_id
    ])
  end

  def encode(backend, pid, mfa, restart, shutdown, type, modules) do
    shutdown_type =
      case shutdown do
        :infinity -> :infinity
        _other -> :timeout
      end

    shutdown_timeout =
      case shutdown do
        :infinity -> 0
        int -> int
      end

    params =
      %{
        supervisor_id: backend.supervisor_id,
        mfargs: :erlang.term_to_binary(mfa),
        pid: :erlang.term_to_binary(pid),
        restart_type: restart,
        shutdown_type: shutdown_type,
        shutdown_timeout: shutdown_timeout,
        child_type: type,
        modules: :erlang.term_to_binary(modules),
        lock_id: backend.lock_id
      }

    Horde.DynamicSupervisorChild.changeset(%Horde.DynamicSupervisorChild{}, params)
  end

  def decode(child) do
    shutdown =
      case child do
        %{shutdown_type: :infinity} -> :infinity
        %{shutdown_type: :timeout, shutdown_timeout: timeout} -> timeout
      end

    {:erlang.binary_to_term(child.pid),
     {
       :erlang.binary_to_term(child.mfargs),
       child.restart_type,
       shutdown,
       child.child_type,
       :erlang.binary_to_term(child.modules)
     }}
  end
end
