defmodule HordePro.Adapter.Postgres.SupervisorBackend do
  defstruct([:repo, :locker_pid, :lock_id])

  import Ecto.Query, only: [from: 2]

  alias HordePro.Adapter.Postgres.Locker
  alias HordePro.Adapter.Postgres.Manager
  require Locker

  def new(repo: repo) do
    %__MODULE__{repo: repo}
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

  defp assign_manager(t) do
    {:ok, manager_pid} =
      Manager.start_link(
        locker_pid: t.locker_pid,
        repo: t.repo,
        lock_namespace: @lock_namespace,
        lock_id: t.lock_id
      )

    t |> Map.put(:manager_pid, manager_pid)
  end

  defp assign_new_lock_id(t) do
    Locker.with_lock t.locker_pid, @global_lock do
      lock_id = Locker.make_lock_32()
      true = Locker.try_lock(t.locker_pid, {@lock_namespace, lock_id})
      t |> Map.put(:lock_id, lock_id)
    end
  end

  defp maybe_empty_process_table(t) do
    Locker.with_lock t.locker_pid, @global_lock do
      all_locks? =
        from(p in HordePro.Process,
          distinct: p.lock_id,
          select: p.lock_id,
          where: not is_nil(p.lock_id)
        )
        |> t.repo.all()
        |> Enum.all?(fn lock_id ->
          Locker.try_lock(t.locker_pid, {@lock_namespace, lock_id})
        end)

      if all_locks? do
        t.repo.delete_all(HordePro.Process)
      end
    end

    t
  end

  def save_child(t, _pid, mfa, restart, shutdown, type, modules) do
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

    params = %{
      mfargs: :erlang.term_to_binary(mfa),
      restart_type: restart,
      shutdown_type: shutdown_type,
      shutdown_timeout: shutdown_timeout,
      child_type: type,
      modules: :erlang.term_to_binary(modules),
      lock_id: t.lock_id
    }

    {:ok, _} =
      HordePro.Process.changeset(%HordePro.Process{}, params)
      |> t.repo.insert()

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
