defmodule HordePro.Adapter.Postgres.Manager do
  @moduledoc false
  use GenServer

  import Ecto.Query, only: [from: 2]
  alias HordePro.Adapter.Postgres.Locker
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
      Keyword.take(opts, [:repo, :locker_pid, :lock_namespace, :lock_id, :supervisor])
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
    from(p in HordePro.Child,
      distinct: p.lock_id,
      select: p.lock_id,
      where: not is_nil(p.lock_id)
    )
    |> t.repo.all()
    |> IO.inspect(label: "LOCK_ID to acquire")
    |> Enum.map(fn lock_id ->
      Locker.with_lock t.locker_pid, {t.lock_namespace, lock_id} do
        from(p in HordePro.Child, where: p.lock_id == ^lock_id)
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
    from(p in HordePro.Child, where: is_nil(p.lock_id))
    |> t.repo.all()
    |> IO.inspect(label: "FREE PROCESSES")
    |> Enum.map(fn child ->
      from(p in HordePro.Child, where: p.id == ^child.id, where: is_nil(p.lock_id))
      |> t.repo.update_all(set: [lock_id: t.lock_id])
      |> IO.inspect(label: "SET LOCK")
      |> case do
        {1, nil} ->
          child

        {0, nil} ->
          nil
      end
    end)
    |> Enum.map(fn child ->
      #
      # start the child here, but in such a way that it doesn't save it a second time.
      #
      # maybe we can start the child here, and then delete the old one.
      # only downside is that the operation isn't atomic. we can end up with duplicates this way. not ideal.
      #
      # but, adding a kind of `:resume_child` handler adds a bunch of code to the DynamicSupervisor that I'd rather not have to deal with.
      #
      IO.inspect(child, label: "RESUME THIS PLS")

      {pid, child} = HordePro.Child.decode(child)

      GenServer.call(t.supervisor, {:resume_child, {pid, child}}, :infinity)
      |> IO.inspect(label: "RESUME_CHILD")
    end)

    t
  end
end
