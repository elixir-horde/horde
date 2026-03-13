defmodule Horde.SignalShutdown do
  @moduledoc false

  use GenServer
  require Logger

  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(options) do
    %{
      id: __MODULE__,
      start: {GenServer, :start_link, [__MODULE__, Keyword.get(options, :signal_to)]}
    }
  end

  @impl GenServer
  @spec init([GenServer.server()]) :: {:ok, [GenServer.server()]}
  def init(signal_to) do
    Process.flag(:trap_exit, true)
    {:ok, signal_to}
  end

  @impl GenServer
  @spec terminate(term(), [GenServer.server()]) :: :ok
  def terminate(_reason, signal_to) do
    Enum.each(signal_to, fn destination ->
      :ok = GenServer.call(destination, :horde_shutting_down)
    end)
  end
end
