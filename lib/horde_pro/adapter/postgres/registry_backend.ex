defmodule HordePro.RegistryBackend do
  # import SqlFmt.Helpers
  import SqlFmt.Helpers

  def register_key(repo, kind, key_ets, key, {key, {pid, value}}) do
    # 1. write the key, and write the event
    # 2. also need to make sure we are up to date with events. So we write the event, and then also ask for all events between the last one we saw, and the one we just inserted.
    query = ~SQL"""
    WITH events_index AS (
      SELECT
        MAX(event_counter) AS max_counter
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
          events_index.max_counter + 1,
          "register_key",
          $5
        )
    )
    SELECT
      *
    FROM
      horde_pro_registry_events
    """

    params = [
      _registry_id = "",
      :erlang.term_to_binary(key),
      :erlang.term_to_binary(pid),
      :erlang.term_to_binary(value),
      kind == :unique,
      :erlang.term_to_binary(_event_body = ""),
      _last_event_counter = 0
    ]

    # query = ~SQL"""
    # WITH mmm AS (
    #   SELECT
    #     event_counter
    #   FROM
    #     horde_pro_registry_events
    #   ORDER BY
    #     event_counter DESC
    #   LIMIT
    #     1
    # )
    # SELECT
    #   *
    # FROM
    #   mmm
    # """

    # params = []

    Ecto.Adapters.SQL.query(repo, query, params)
    |> IO.inspect(label: "QUERY")

    IO.inspect(repo)
    IO.inspect(kind)
    IO.inspect(key_ets)
    IO.inspect(key)
    IO.inspect(pid)
    IO.inspect(value)
    :ok
  end
end
