defmodule HordePro.Adapter.Postgres.SupervisorBackend do
  defstruct([:repo, :locker_pid, :lock_id])

  def new(repo: repo) do
    %__MODULE__{repo: repo}
  end

  def init(t) do
    {:ok, locker_pid} = HordePro.Adapter.Postgres.Locker.start_link(repo: t.repo)
    lock_id = HordePro.Adapter.Postgres.Locker.make_lock_id()
    true = HordePro.Adapter.Postgres.Locker.try_lock(locker_pid, lock_id)
    t |> Map.merge(%{locker_pid: locker_pid, lock_id: lock_id})
  end

  def save_child(t, _pid, mfa, restart, shutdown, type, modules) do
    %{
      mfa: :erlang.term_to_binary(mfa),
      restart: restart,
      shutdown: shutdown,
      child_type: type,
      modules: :erlang.term_to_binary(modules),
      lock_id: t.lock_id
    }

    :ok
  end

  def terminate(%{locker_pid: locker_pid} = _t) do
    monitor = Process.monitor(locker_pid)
    Process.exit(locker_pid, :shutdown)

    receive do
      {:DOWN, ^monitor, :process, ^locker_pid, _reason} ->
        :ok
    after
      5000 ->
        Process.exit(locker_pid, :kill)

        receive do
          {:DOWN, ^monitor, :process, ^locker_pid, _reason} ->
            :ok
        end
    end
  end
end
