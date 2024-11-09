defmodule HordePro.Adapter.Postgres.RegistryBackend do
  @moduledoc false

  import SqlFmt.Helpers

  defstruct([:repo, :registry_id, :partition, :locker_pid, :lock_id])

  def new(opts) do
    struct!(__MODULE__, opts |> Enum.into(%{}))
  end

  @doc """
  This function is called once to set up what can be set up from the RegistrySupervisor init function.

  The output is intended for `init_partition/2`
  """
  def init(t, opts) do
    struct!(t, opts |> Enum.into(%{}))
  end

  def register_key(backend, kind, _key_ets, key, {key, {pid, value}}) do
    # 1. write the key, and write the event
    # 2. also need to make sure we are up to date with events. So we write the event, and then also ask for all events between the last one we saw, and the one we just inserted.
    query = ~SQL"""
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
        horde_pro_registry_events (
          registry_id,
          event_counter,
          event_type,
          event_body
        )
      VALUES
        (
          $1,
          (
            SELECT
              max_counter
            FROM
              events_index
          ) + 1,
          'register_key',
          $6
        )
      RETURNING
        *
    )
    SELECT
      *
    FROM
      horde_pro_registry_events
    WHERE
      registry_id = $1
      AND event_counter > $7
    UNION
    SELECT
      *
    FROM
      new_events
    ORDER BY
      event_counter ASC
    """

    params = [
      _registry_id = backend.registry_id <> backend.partition,
      :erlang.term_to_binary(key),
      :erlang.term_to_binary(pid),
      :erlang.term_to_binary(value),
      kind == :unique,
      :erlang.term_to_binary(_event_body = ""),
      _last_event_counter = 0
    ]

    rows =
      case _result = Ecto.Adapters.SQL.query(backend.repo, query, params) do
        {:ok, %{rows: rows}} -> rows
      end

    # IO.inspect(result, label: "RESULT")
    # IO.inspect(backend.repo)
    # IO.inspect(kind)
    # IO.inspect(key_ets)
    # IO.inspect(key)
    # IO.inspect(pid)
    # IO.inspect(value)
    IO.inspect(rows, label: "ROWS")
    {:ok, rows}
  end
end
