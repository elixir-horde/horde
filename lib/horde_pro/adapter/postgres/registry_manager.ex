defmodule HordePro.Adapter.Postgres.RegistryManager do
  @moduledoc false
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @tick_interval 1000
  def init(opts) do
    schedule_tick()

    # TODO load entire registry table, fetch latest event # too.

    t =
      Keyword.take(opts, [])
      |> Enum.into(%{})

    {:ok, t |> load_registry()}
  end

  defp load_registry(t) do
    t
  end

  # def handle_call(:register, 

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
