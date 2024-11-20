defmodule HordePro.Adapter.Postgres.RegistryManager do
  @moduledoc false
  use GenServer

  import Ecto.Query, only: [from: 2]

  require HordePro.Adapter.Postgres.Locker

  alias HordePro.Adapter.Postgres.Locker

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  defstruct [:event_counter, :backend]

  @tick_interval 1000
  def init(opts) do
    schedule_tick()

    t =
      Keyword.take(opts, [:backend])
      |> Enum.into(%{event_counter: 0})

    {:ok, t |> listen() |> load_registry()}
  end

  defp listen(t) do
    true =
      Locker.listen(t.backend.locker_pid, t.backend.registry_id <> to_string(t.backend.partition))

    t
  end

  defp load_registry(t) do
    {registry, event_counter} =
      HordePro.Adapter.Postgres.RegistryBackend.get_registry(t.backend)

    HordePro.Adapter.Postgres.RegistryBackend.init_registry(t.backend, registry)

    Map.put(t, :event_counter, event_counter)
  end

  defp schedule_tick() do
    Process.send_after(self(), :tick, @tick_interval)
  end

  def handle_info(:tick, t) do
    schedule_tick()
    acquire_locks(t)
    {:noreply, t}
  end

  def handle_info({:notice, _channel, "UPDATE"}, t) do
    new_counter = HordePro.Adapter.Postgres.RegistryBackend.get_events(t.backend, t.event_counter)

    {:noreply, %{t | event_counter: new_counter}}
  end

  defp acquire_locks(t) do
    registry_id = t.backend.registry_id <> to_string(t.backend.partition)

    from(p in HordePro.Registry.Process,
      distinct: p.lock_id,
      select: p.lock_id,
      where: p.registry_id == ^registry_id
    )
    |> t.backend.repo.all()
    |> Enum.map(fn lock_id ->
      Locker.with_lock t.backend.locker_pid, {t.backend.lock_namespace, lock_id} do
        from(p in HordePro.Registry.Process,
          where: p.lock_id == ^lock_id,
          where: p.registry_id == ^registry_id
        )
        |> t.backend.repo.all()
        |> Enum.map(fn process ->
          HordePro.Adapter.Postgres.RegistryBackend.unregister_key(
            t.backend,
            :erlang.binary_to_term(process.key),
            :erlang.binary_to_term(process.pid),
            fn -> nil end
          )
        end)
      end
    end)
  end
end
