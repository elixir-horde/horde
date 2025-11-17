defmodule Horde.Adapter.Postgres.DynamicSupervisorManager do
  @moduledoc false
  use GenServer

  import Ecto.Query, only: [from: 2]
  alias Horde.Adapter.Postgres.Locker
  require Locker

  # This module is responsible for performing periodic clean-up.
  #
  # Task 1: attempt to acquire lock; if acquired, clear out all children and release.
  #
  # Task 2: attempt to claim children with no lock_id, if it should be started by this supervisor.

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @tick_interval 2000
  def init(opts) do
    schedule_tick()

    t =
      Keyword.take(opts, [
        :repo,
        :locker_pid,
        :lock_namespace,
        :lock_id,
        :supervisor_pid,
        :supervisor_id
      ])
      |> Enum.into(%{})

    {:ok, t}
  end

  defp schedule_tick() do
    Process.send_after(self(), :tick, @tick_interval)
  end

  def handle_info(:tick, t) do
    schedule_tick()
    acquire_locks(t)
    handle_disowned_children(t)
    {:noreply, t}
  end

  defp acquire_locks(t) do
    from(c in Horde.DynamicSupervisorChild,
      distinct: c.lock_id,
      select: c.lock_id,
      where: not is_nil(c.lock_id),
      where: c.supervisor_id == ^t.supervisor_id
    )
    |> t.repo.all()
    |> Enum.map(fn lock_id ->
      Locker.with_lock t.locker_pid, {t.lock_namespace, lock_id} do
        from(c in Horde.DynamicSupervisorChild,
          where: c.lock_id == ^lock_id,
          where: c.supervisor_id == ^t.supervisor_id
        )
        |> t.repo.update_all(set: [lock_id: nil])
      end
    end)
  end

  defp handle_disowned_children(t) do
    #
    # TODO add node selection here
    #
    # First we reserve the child here. Only then do we ask the supervisor to start the child.
    #
    # If we crash, then the lock will be reset by the manager on another node.
    #
    from(c in Horde.DynamicSupervisorChild,
      where: is_nil(c.lock_id),
      where: c.supervisor_id == ^t.supervisor_id
    )
    |> t.repo.all()
    |> Enum.map(fn child ->
      from(c in Horde.DynamicSupervisorChild,
        where: c.id == ^child.id,
        where: is_nil(c.lock_id),
        where: c.supervisor_id == ^t.supervisor_id
      )
      |> t.repo.update_all(set: [lock_id: t.lock_id])
      |> case do
        {1, nil} ->
          child

        {0, nil} ->
          nil
      end
    end)
    |> Enum.map(fn child ->
      {pid, child} = Horde.DynamicSupervisorChild.decode(child)

      GenServer.call(t.supervisor_pid, {:resume_child, {pid, child}}, :infinity)
    end)

    t
  end
end
