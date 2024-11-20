defmodule HordePro.Adapter.Postgres.RegistryBackend do
  @moduledoc false

  require HordePro.Adapter.Postgres.Locker
  import Ecto.Query, only: [from: 2]

  alias HordePro.Adapter.Postgres.Locker
  alias HordePro.Adapter.Postgres.RegistryManager

  defstruct([
    :repo,
    :registry,
    :registry_id,
    :partition,
    :locker_pid,
    :lock_id,
    :lock_namespace,
    :key_ets,
    :pid_ets,
    :kind
  ])

  def new(opts) do
    struct!(__MODULE__, opts |> Enum.into(%{}))
  end

  def init(t, opts) do
    struct!(t, opts |> Enum.into(%{}))
    |> assign_locker()
    |> assign_new_lock_id()
    |> assign_manager()
  end

  defp assign_locker(t) do
    {:ok, locker_pid} = Locker.start_link(repo: t.repo)
    t |> Map.put(:locker_pid, locker_pid)
  end

  # TODO make these configurable
  @lock_namespace 993_400

  @max_attempts 5
  defp assign_new_lock_id(t, attempts \\ @max_attempts)

  defp assign_new_lock_id(t, attempts) when attempts > 0 do
    lock_id = Locker.make_lock_32()
    true = Locker.try_lock(t.locker_pid, {@lock_namespace, lock_id})
    t |> Map.put(:lock_id, lock_id) |> Map.put(:lock_namespace, @lock_namespace)
  end

  defp assign_new_lock_id(_t, _lt_zero) do
    raise "Could not acquire global lock"
  end

  defp assign_manager(t) do
    {:ok, manager_pid} =
      RegistryManager.start_link(backend: t)

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
      _registry_id = backend.registry_id <> to_string(backend.partition),
      _key = :erlang.term_to_binary(key),
      _pid = :erlang.term_to_binary(pid),
      _value = :erlang.term_to_binary(value),
      _unique = kind == :unique,
      _event = :erlang.term_to_binary(event),
      _last_event_counter = 0,
      _lock_id = backend.lock_id
    ]

    import SqlFmt.Helpers

    query = ~SQL"""
    WITH events_index AS (
      SELECT
        COALESCE(MAX(event_counter), 0) AS max_counter
      FROM
        horde_pro_registry_events
      WHERE
        registry_id = $1
    ),
    insert_processes AS (
      INSERT INTO
        horde_pro_registry_processes (registry_id, KEY, pid, value, is_unique, lock_id)
      VALUES
        ($1, $2, $3, $4, $5, $8)
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

  def unregister_key(backend, key, self, fun) do
    event = %{
      type: :remove_key,
      key: key,
      pid: self
    }

    params = [
      _registry_id = backend.registry_id <> to_string(backend.partition),
      _key = :erlang.term_to_binary(key),
      _pid = :erlang.term_to_binary(self),
      _event = :erlang.term_to_binary(event),
      _last_event_counter = 0
    ]

    import SqlFmt.Helpers

    query = ~SQL"""
    WITH events_index AS (
      SELECT
        COALESCE(MAX(event_counter), 0) AS max_counter
      FROM
        horde_pro_registry_events
      WHERE
        registry_id = $1
    ),
    delete_processes AS (
      DELETE FROM
        horde_pro_registry_processes
      WHERE
        registry_id = $1
        AND KEY = $2
        AND pid = $3
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
          $4
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
      AND event_counter > $5
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
      case Ecto.Adapters.SQL.query(backend.repo, query, params) do
        {:ok, %{rows: rows}} ->
          fun.()
          rows
      end
      |> Enum.map(fn [event_body, _event_counter] ->
        :erlang.binary_to_term(event_body)
      end)

    {:ok, events}
  end

  def get_events(t, event_counter) do
    registry_id = t.registry_id <> to_string(t.partition)

    new_events =
      from(e in HordePro.Registry.Event,
        where: e.registry_id == ^registry_id,
        where: e.event_counter > ^event_counter,
        order_by: {:desc, e.event_counter},
        select: e.event_body
      )
      |> t.repo.all()

    events =
      Enum.reduce(new_events, [], fn event, events ->
        [:erlang.binary_to_term(event) | events]
      end)

    HordePro.Registry.replay_events(t.registry, t.partition, events)

    _new_event_counter =
      case new_events do
        [event | _] ->
          :erlang.binary_to_term(event) |> Map.get(:event_counter)

        _ ->
          event_counter
      end
  end

  def get_registry(t) do
    params = [
      _registry_id = t.registry_id <> to_string(t.partition)
    ]

    # import SqlFmt.Helpers

    query = """
    WITH events_index AS (
      SELECT
        COALESCE(MAX(event_counter), 0) AS max_counter
      FROM
        horde_pro_registry_events
      WHERE
        registry_id = $1
    )
    SELECT
      (
        SELECT
          max_counter
        FROM
          events_index
      ) AS max_counter,
      KEY,
      pid,
      value
    FROM
      horde_pro_registry_processes
    WHERE
      registry_id = $1
    """

    rows =
      case _result = Ecto.Adapters.SQL.query(t.repo, query, params) do
        {:ok, %{rows: rows}} ->
          rows
      end

    max_counter =
      case rows do
        [[max_counter | _] | _] -> max_counter
        _ -> 0
      end

    registry =
      rows
      |> Enum.map(fn [_max_counter, key, pid, value] ->
        %{
          key: :erlang.binary_to_term(key),
          pid: :erlang.binary_to_term(pid),
          value: :erlang.binary_to_term(value)
        }
      end)

    {registry, max_counter}
  end

  def init_registry(t, entries) do
    HordePro.Registry.init_registry(t.kind, t.pid_ets, t.key_ets, entries)
  end

  def terminate(t) do
    stop_child(t.locker_pid)
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
