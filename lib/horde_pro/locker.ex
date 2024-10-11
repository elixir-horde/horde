defmodule HordePro.Locker do
  @moduledoc false

  alias Postgrex.SimpleConnection

  @behaviour SimpleConnection

  @timeout 5000
  @type t :: any()
  @type lock_id :: String.t()

  def start_link(repo: repo) do
    config = repo.config()

    opts = config |> Keyword.merge(auto_reconnect: false)
    SimpleConnection.start_link(__MODULE__, :no_arg, opts)
  end

  @spec try_lock(t(), lock_id()) :: :ok | {:error, any()}
  def try_lock(locker, lock_id) do
    SimpleConnection.call(locker, {:try_lock, lock_id}, @timeout)
  end

  def which_locks(locker) do
    SimpleConnection.call(locker, :which_locks, @timeout)
  end

  ### SERVER CALLBACKS ###

  @impl SimpleConnection
  def init(:no_arg) do
    {:ok, %{from: nil, locks: [], requested_lock_id: nil}}
  end

  @impl SimpleConnection
  def handle_call({:try_lock, lock_id}, from, state) do
    {:query, try_lock_query(lock_id), %{state | from: from, requested_lock_id: lock_id}}
  end

  def handle_call(:which_locks, from, state) do
    SimpleConnection.reply(from, state.locks)
    {:noreply, state}
  end

  @impl SimpleConnection
  def handle_result(results, state) when is_list(results) do
    case results do
      [%{rows: [["t"]]}] ->
        SimpleConnection.reply(state.from, true)

        {:noreply,
         %{
           state
           | locks: [state.requested_lock_id | state.locks],
             from: nil,
             requested_lock_id: nil
         }}

      [%{rows: [["f"]]}] ->
        SimpleConnection.reply(state.from, false)
        {:noreply, %{state | from: nil, requested_lock_id: nil}}
    end
  end

  @impl SimpleConnection
  def notify(_, _, state) do
    {:noreply, state}
  end

  @lock_namespace :erlang.phash2("horde_pro")

  defp try_lock_query(lock_name) do
    "select pg_try_advisory_lock(#{@lock_namespace}, #{:erlang.phash2(lock_name)})"
  end
end
