defmodule HordePro.Adapter.Postgres.DynamicSupervisor do
  def init(repo) do
    {:ok, locker} = HordePro.Adapter.Postgres.Locker.start_link(repo: repo)
    lock_id = HordePro.Adapter.Postgres.Locker.make_lock_id()
    true = HordePro.Adapter.Postgres.Locker.try_lock(locker, lock_id)
    {locker, lock_id}
  end

  def save_child(_pid, mfa, restart, shutdown, type, modules, state) do
    %{
      mfa: :erlang.term_to_binary(mfa),
      restart: restart,
      shutdown: shutdown,
      child_type: type,
      modules: :erlang.term_to_binary(modules),
      lock_id: state.lock_id
    }

    :ok
  end
end
