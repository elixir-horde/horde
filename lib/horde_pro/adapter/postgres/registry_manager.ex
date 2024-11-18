defmodule HordePro.Adapter.Postgres.RegistryManager do
  @moduledoc false
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  defstruct [:event_counter, :backend]

  @tick_interval 1000
  def init(opts) do
    schedule_tick()

    # TODO load entire registry table, fetch latest event # too.

    t =
      Keyword.take(opts, [:backend])
      |> Enum.into(%{event_counter: 0})

    {:ok, t |> load_registry()}
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
    # acquire_locks(t)
    # handle_disowned_children(t)
    {:noreply, t}
  end
end
