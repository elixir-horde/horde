defmodule HordePro.Adapter.Postgres.DynamicSupervisorBackend do
  #
  # NOTES:
  #
  # Strategy:
  # lock_id = gen_id() |> acquire_lock()
  #
  # when we start a process, we record it under this lock_id
  #
  # periodically, try to acquire locks with pg_try_advisory_lock()
  # if we get the lock, we redistribute all processes to the appropriate node.
  # need to figure out what to do with the lock_id for each process.
  #
  # maybe this can be two processes running in parallel. first process: try selecting locks, if it gets one, simply clear the lock_id from the processes having this lock_id.
  # second process: select processes having no lock_id and see if you can own them, starting them and setting the lock on them when your select_node matches yourself.
  #
  # This might have the drawback that processes don't get shut down when the entire system reboots. But perhaps this is ok? I'm not sure. Maybe I can find a way to figure out when the entire cluster has shut down, and then clear processes that are not running.
  #
  # Perhaps if all locks can be acquired on boot, it simply truncates the table? Going to have to be careful of race conditions here. Maybe we have 1 lock to register, and in that way we can serialize registering. Then we can acquire the lock, check if we get all other locks, if that is the case, we truncate. Only after we register our own node lock, do we release the global lock. Race condition sorted!
  #

  defstruct([:repo, :supervisor_id, :locker_pid, :lock_id])

  import Ecto.Query, only: [from: 2]

  alias HordePro.Adapter.Postgres.Locker
  alias HordePro.Adapter.Postgres.DynamicSupervisorManager
  require Locker

  def new(opts) do
    struct!(__MODULE__, opts |> Enum.into(%{}))
  end

  def init(t) do
    t
    |> assign_locker()
    |> assign_new_lock_id()
    |> maybe_empty_process_table()
    |> assign_manager()
  end

  defp assign_locker(t) do
    {:ok, locker_pid} = Locker.start_link(repo: t.repo)
    t |> Map.put(:locker_pid, locker_pid)
  end

  # TODO make these configurable
  @lock_namespace 993_399
  @global_lock 92_929_292

  @max_attempts 5

  defp assign_manager(t) do
    {:ok, manager_pid} =
      DynamicSupervisorManager.start_link(
        locker_pid: t.locker_pid,
        repo: t.repo,
        lock_namespace: @lock_namespace,
        lock_id: t.lock_id,
        supervisor_pid: self(),
        supervisor_id: t.supervisor_id
      )

    t |> Map.put(:manager_pid, manager_pid)
  end

  defp assign_new_lock_id(t, attempts \\ @max_attempts)

  defp assign_new_lock_id(t, attempts) when attempts > 0 do
    Locker.with_lock t.locker_pid, @global_lock do
      lock_id = Locker.make_lock_32()
      true = Locker.try_lock(t.locker_pid, {@lock_namespace, lock_id})
      t |> Map.put(:lock_id, lock_id)
    end
    |> case do
      false ->
        Process.sleep(20)
        assign_new_lock_id(t, attempts - 1)

      %{} = t ->
        t
    end
  end

  defp assign_new_lock_id(_t, _lt_zero) do
    raise "Could not acquire global lock"
  end

  defp maybe_empty_process_table(t) do
    Locker.with_lock t.locker_pid, @global_lock do
      all_locks =
        from(c in HordePro.DynamicSupervisorChild,
          distinct: c.lock_id,
          select: c.lock_id,
          where: c.supervisor_id == ^t.supervisor_id,
          where: not is_nil(c.lock_id)
        )
        |> t.repo.all()

      all_locks? =
        all_locks
        |> Enum.all?(fn lock_id ->
          Locker.try_lock(t.locker_pid, {@lock_namespace, lock_id})
        end)

      if all_locks != [] and all_locks? do
        from(c in HordePro.DynamicSupervisorChild, where: c.supervisor_id == ^t.supervisor_id)
        |> t.repo.delete_all()
      end

      Enum.each(all_locks, fn lock_id ->
        Locker.release(t.locker_pid, {@lock_namespace, lock_id})
      end)
    end

    t
  end

  def save_child(t, pid, mfa, restart, shutdown, type, modules) do
    {:ok, _} =
      HordePro.DynamicSupervisorChild.encode(t, pid, mfa, restart, shutdown, type, modules)
      |> t.repo.insert()

    :ok
  end

  def delete_child(t, pid) do
    binary_pid = :erlang.term_to_binary(pid)

    {1, nil} =
      from(c in HordePro.DynamicSupervisorChild,
        where: c.pid == ^binary_pid,
        where: c.lock_id == ^t.lock_id,
        where: c.supervisor_id == ^t.supervisor_id
      )
      |> t.repo.delete_all()

    :ok
  end

  def terminate(t) do
    stop_child(t.locker_pid)
    stop_child(t.manager_pid)
  end

  defp stop_child(pid) do
    monitor = Process.monitor(pid)
    Process.exit(pid, :shutdown)

    receive do
      {:DOWN, ^monitor, :process, ^pid, _reason} ->
        :ok
    after
      5000 ->
        Process.exit(pid, :kill)

        receive do
          {:DOWN, ^monitor, :process, ^pid, _reason} ->
            :ok
        end
    end
  end
end
