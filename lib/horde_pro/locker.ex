defmodule HordePro.Locker do
  @moduledoc false

  alias Postgrex.SimpleConnection

  @behaviour SimpleConnection

  @call_opts []
  @type t :: any()
  @type lock_id :: String.t()

  def start_link(repo: repo) do
    config =
      repo.config()
      |> IO.inspect()

    opts = config |> Keyword.merge(auto_reconnect: false) |> IO.inspect(label: "config")
    SimpleConnection.start_link(__MODULE__, :no_arg, opts)
  end

  @spec get_lock(t(), lock_id()) :: :ok | {:error, any()}
  def get_lock(locker, lock_id) do
    SimpleConnection.call(locker, {:get_lock, lock_id}, @call_opts)
  end

  def which_locks(locker) do
    SimpleConnection.call(locker, :which_locks, @call_opts)
  end

  ### SERVER CALLBACKS ###

  @impl SimpleConnection
  def init(:no_arg) do
    {:ok, %{from: nil, locks: [], requested_lock_id: nil}}
  end

  @impl SimpleConnection
  def handle_call({:get_lock, lock_id}, from, state) do
    {:query, get_lock_query(lock_id), %{state | from: from, requested_lock_id: lock_id}}
  end

  def handle_call(:which_locks, from, state) do
    SimpleConnection.reply(from, state.locks)
    {:noreply, state}
  end

  @impl SimpleConnection
  def handle_result(results, state) when is_list(results) do
    case results do
      [%{rows: [["t"]]}] ->
        SimpleConnection.reply(state.from, :ok)

        {:noreply,
         %{
           state
           | locks: [state.requested_lock_id | state.locks],
             from: nil,
             requested_lock_id: nil
         }}

      [%{rows: [["f"]]}] ->
        SimpleConnection.reply(state.from, {:error, "lock could not be acquired"})
        {:noreply, %{state | from: nil, requested_lock_id: nil}}
    end
  end

  @impl SimpleConnection
  def notify(_, _, state) do
    {:noreply, state}
  end

  defp get_lock_query(state) do
    "select '#{state.name}', pg_try_advisory_lock(1, #{:erlang.phash2(state.name)})"
  end
end
