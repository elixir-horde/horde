defmodule HordePro.Adapter.Postgres.Manager do
  @moduledoc false
  use GenServer

  import Ecto.Query, only: [from: 2]
  alias HordePro.Adapter.Postgres.Locker
  require Locker

  # This module is responsible for performing periodic clean-up.
  #
  # Task 1: attempt to acquire lock; if acquired, clear out all processes and release.
  #
  # Task 2: attempt to claim processes with no lock_id, if it should be started by this supervisor.

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @tick_interval 2000
  def init(opts) do
    schedule_tick()
    t = Keyword.take(opts, [:repo, :locker_pid, :lock_namespace, :lock_id]) |> Enum.into(%{})
    {:ok, t}
  end

  defp schedule_tick() do
    Process.send_after(self(), :tick, @tick_interval)
  end

  def handle_info(:tick, t) do
    schedule_tick()
    acquire_locks(t)
    handle_disowned_processes(t)
    {:noreply, t}
  end

  defp acquire_locks(t) do
    from(p in HordePro.Process,
      distinct: p.lock_id,
      select: p.lock_id,
      where: not is_nil(p.lock_id)
    )
    |> t.repo.all()
    |> Enum.map(fn lock_id ->
      Locker.with_lock t.locker_pid, {t.lock_namespace, lock_id} do
        from(p in HordePro.Process, where: p.lock_id == ^lock_id)
        |> t.repo.update_all(set: [lock_id: nil])
      end
    end)
  end

  defp handle_disowned_processes(t) do
    #
    # TODO add node selection here
    #
    # First we reserve the process here. Only then do we ask the supervisor to start the process.
    #
    # If we crash, then the lock will be reset by the manager on another node.
    #
    from(p in HordePro.Process, where: is_nil(p.lock_id))
    |> t.repo.all()
    |> IO.inspect(label: "FREE PROCESSES")
    |> Enum.map(fn process ->
      from(p in HordePro.Process, where: p.id == ^process.id, where: is_nil(p.lock_id))
      |> t.repo.update_all(set: [lock_id: t.lock_id])
      |> IO.inspect(label: "SET LOCK")
      |> case do
        {1, nil} ->
          process

        {0, nil} ->
          nil
      end
    end)
    |> Enum.map(fn _process ->
      # TODO start the process here, but in such a way that it doesn't save it a second time.
      nil
    end)

    t
  end
end
