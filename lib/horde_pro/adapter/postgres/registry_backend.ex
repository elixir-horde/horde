defmodule HordePro.Adapter.Postgres.RegistryBackend do
  @moduledoc false

  import SqlFmt.Helpers

  alias HordePro.Adapter.Postgres.RegistryManager

  defstruct([:repo, :registry_id, :partition, :locker_pid, :lock_id])

  def new(opts) do
    struct!(__MODULE__, opts |> Enum.into(%{}))
  end

  @doc """
  This function is called once to set up what can be set up from the RegistrySupervisor init function.

  The output is intended for `init_partition/2`
  """
  def init(t, opts) do
    # TODO load registry on startup
    struct!(t, opts |> Enum.into(%{}))
    |> assign_manager()
  end

  defp assign_manager(t) do
    {:ok, manager_pid} =
      RegistryManager.start_link(
        # locker_pid: t.locker_pid,
        repo: t.repo
        # lock_namespace: @lock_namespace,
        # lock_id: t.lock_id,
        # supervisor_pid: self(),
        # supervisor_id: t.supervisor_id
      )

    t |> Map.put(:manager_pid, manager_pid)
  end

  def register_key(backend, kind, _key_ets, key, {key, {pid, value}}) do
    # 1. write the key, and write the event
    # 2. also need to make sure we are up to date with events. So we write the event, and then also ask for all events between the last one we saw, and the one we just inserted.
    event = %{
      type: :insert_key,
      kind: kind,
      key: key,
      pid: pid,
      value: value
    }

    params = [
      _registry_id = backend.registry_id <> backend.partition,
      _key = :erlang.term_to_binary(key),
      _pid = :erlang.term_to_binary(pid),
      _value = :erlang.term_to_binary(value),
      _unique = kind == :unique,
      _event = :erlang.term_to_binary(event),
      _last_event_counter = 0
    ]

    query = """
    WITH events_index AS (
      SELECT
        COALESCE(MAX(event_counter), 0) AS max_counter
      FROM
        horde_pro_registry_events
      WHERE
        registry_id = $1
    ),
    x AS (
      INSERT INTO
        horde_pro_registry_processes (registry_id, KEY, pid, value, is_unique)
      VALUES
        ($1, $2, $3, $4, $5)
    ),
    new_events AS (
      INSERT INTO
        horde_pro_registry_events (registry_id, event_counter, event_body)
      VALUES
        (
          $1,
          (
            SELECT
              max_counter
            FROM
              events_index
          ) + 1,
          $6
        )
      RETURNING
        *
    )
    SELECT
      event_body,
      event_counter
    FROM
      horde_pro_registry_events
    WHERE
      registry_id = $1
      AND event_counter > $7
    UNION
    SELECT
      event_body,
      event_counter
    FROM
      new_events
    ORDER BY
      event_counter ASC
    """

    events =
      case _result = Ecto.Adapters.SQL.query(backend.repo, query, params) do
        {:ok, %{rows: rows}} -> rows
      end
      |> Enum.map(fn [event_body, _event_counter] ->
        :erlang.binary_to_term(event_body)
      end)

    {:ok, events}
  end

  def unregister_key(_backend, fun) do
    fun.()
  end

  def terminate(t) do
    # stop_child(t.locker_pid)
    IO.inspect("TERMINATING")
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
