defmodule HordePro.Adapter.Postgres.Locker do
  @moduledoc false

  alias Postgrex.SimpleConnection

  @behaviour SimpleConnection

  @timeout 5000
  @type t :: any()
  @type lock_id :: integer() | {integer(), integer()}

  def start_link(repo: repo) do
    config = repo.config()

    opts = config |> Keyword.merge(auto_reconnect: false)
    SimpleConnection.start_link(__MODULE__, :no_arg, opts)
  end

  @spec try_lock(t(), lock_id()) :: :ok | {:error, any()}
  def try_lock(locker, lock_id) do
    SimpleConnection.call(locker, {:try_lock, lock_id}, @timeout)
  end

  def release(locker, lock_id) do
    SimpleConnection.call(locker, {:release, lock_id}, @timeout)
  end

  @max_int Integer.pow(2, 32) - 1

  def make_lock_32() do
    # :rand.uniform returns an unsigned integer. We want a signed integer with the same number of bits.
    <<x::signed-32>> = <<:rand.uniform(@max_int)::unsigned-32>>

    x
  end

  defmacro with_lock(locker, lock_id, do: block) do
    quote do
      try do
        if HordePro.Adapter.Postgres.Locker.try_lock(unquote(locker), unquote(lock_id)) do
          unquote(block)
        else
          false
        end
      after
        HordePro.Adapter.Postgres.Locker.release(unquote(locker), unquote(lock_id))
      end
    end
  end

  ### SERVER CALLBACKS ###

  @impl SimpleConnection
  def init(:no_arg) do
    {:ok, %{from: nil, requested_lock_id: nil, releasing_lock_id: nil}}
  end

  @impl SimpleConnection
  def handle_call({:try_lock, lock_id}, from, state) do
    {:query, try_lock_query(lock_id), %{state | from: from, requested_lock_id: lock_id}}
  end

  def handle_call({:release, lock_id}, from, state) do
    {:query, release_query(lock_id), %{state | from: from, releasing_lock_id: lock_id}}
  end

  @impl SimpleConnection
  def handle_result(results, state = %{requested_lock_id: r})
      when not is_nil(r) and is_list(results) do
    case results do
      [%{rows: [["t"]]}] ->
        SimpleConnection.reply(state.from, true)

        {:noreply, %{state | from: nil, requested_lock_id: nil}}

      [%{rows: [["f"]]}] ->
        SimpleConnection.reply(state.from, false)
        {:noreply, %{state | from: nil, requested_lock_id: nil}}
    end
  end

  def handle_result(results, state = %{releasing_lock_id: r})
      when not is_nil(r) and is_list(results) do
    case results do
      [%{rows: [["t"]]}] ->
        SimpleConnection.reply(state.from, true)

        {:noreply, %{state | from: nil, releasing_lock_id: nil}}

      [%{rows: [["f"]]}] ->
        SimpleConnection.reply(state.from, false)
        {:noreply, %{state | from: nil, releasing_lock_id: nil}}
    end
  end

  @impl SimpleConnection
  def notify(_, _, state) do
    {:noreply, state}
  end

  # @lock_namespace :erlang.phash2("horde_pro")

  #
  # https://www.postgresql.org/docs/current/functions-admin.html#FUNCTIONS-ADVISORY-LOCKS
  #

  defp try_lock_query({l1, l2}) do
    "select pg_try_advisory_lock(#{l1}, #{l2})"
  end

  defp try_lock_query(l1) do
    "select pg_try_advisory_lock(#{l1})"
  end

  defp release_query({l1, l2}) do
    "select pg_advisory_unlock(#{l1}, #{l2})"
  end

  defp release_query(l1) do
    "select pg_advisory_unlock(#{l1})"
  end
end
