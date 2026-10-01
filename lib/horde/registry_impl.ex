defmodule Horde.RegistryImpl do
  @moduledoc false

  use GenServer

  require Logger

  defmodule State do
    @moduledoc false

    @type t :: %__MODULE__{
            name: atom() | nil,
            nodes: MapSet.t(node()),
            members: MapSet.t({atom(), node()}),
            registry_ets_table: atom() | nil,
            pids_ets_table: atom() | nil,
            keys_ets_table: atom() | nil,
            members_ets_table: atom() | nil,
            listeners: [atom()]
          }

    defstruct name: nil,
              nodes: MapSet.new(),
              members: MapSet.new(),
              registry_ets_table: nil,
              pids_ets_table: nil,
              keys_ets_table: nil,
              members_ets_table: nil,
              listeners: []
  end

  @spec child_spec(options :: list()) :: Supervisor.child_spec()
  def child_spec(options \\ []) do
    %{
      id: Keyword.get(options, :name, __MODULE__),
      start: {__MODULE__, :start_link, [options]}
    }
  end

  @spec start_link(options :: list()) :: GenServer.on_start()
  def start_link(options \\ []) do
    name = Keyword.get(options, :name)

    if !is_atom(name) || is_nil(name) do
      raise ArgumentError, "expected :name to be given and to be an atom, got: #{inspect(name)}"
    end

    GenServer.start_link(__MODULE__, options, name: name)
  end

  def on_diffs(name, diffs) do
    try do
      Kernel.send(name, {:crdt_update, diffs})
    rescue
      ArgumentError ->
        # the process might already been stopped
        :ok
    end
  end

  ### GenServer callbacks

  def init(opts) do
    Process.flag(:trap_exit, true)

    name = Keyword.get(opts, :name)
    pids_name = :"pids_#{name}"
    keys_name = :"keys_#{name}"
    members_name = :"members_#{name}"
    listeners = Keyword.get(opts, :listeners, [])

    unless is_list(listeners) and Enum.all?(listeners, &is_atom/1) do
      raise ArgumentError,
            "expected :listeners to be a list of named processes, got: #{inspect(listeners)}"
    end

    Logger.info("Starting #{inspect(__MODULE__)} with name #{inspect(name)}")

    unless is_atom(name) do
      raise ArgumentError, "expected :name to be given and to be an atom, got: #{inspect(name)}"
    end

    :ets.new(name, [:named_table, {:read_concurrency, true}])
    :ets.new(pids_name, [:named_table, {:read_concurrency, true}])
    :ets.new(keys_name, [:named_table, {:read_concurrency, true}])
    :ets.new(members_name, [:named_table, {:read_concurrency, true}])

    state = %State{
      name: name,
      registry_ets_table: name,
      pids_ets_table: pids_name,
      keys_ets_table: keys_name,
      members_ets_table: members_name,
      listeners: listeners
    }

    state =
      case Keyword.get(opts, :members) do
        nil ->
          state

        :auto ->
          state.name
          |> Horde.NodeListener.make_members()
          |> set_initial_members(state)

        members ->
          set_initial_members(members, state)
      end

    case Keyword.get(opts, :meta) do
      nil ->
        nil

      meta ->
        Enum.each(meta, fn {key, value} -> put_meta(state, key, value) end)
    end

    {:ok, state}
  end

  def handle_info({:crdt_update, diffs}, state) do
    new_state = process_diffs(state, diffs)
    {:noreply, new_state}
  end

  def handle_info({:EXIT, pid, _reason}, state) do
    case :ets.take(state.pids_ets_table, pid) do
      [{_pid, keys}] ->
        DeltaCrdt.drop(
          crdt_name(state.name),
          Enum.map(keys, fn key -> {:key, key} end),
          :infinity
        )

        Enum.each(keys, fn key ->
          :ets.match_delete(state.keys_ets_table, {key, :_, {pid, :_}})

          for listener <- state.listeners do
            send(listener, {:unregister, state.name, key, pid})
          end
        end)

      _ ->
        nil
    end

    {:noreply, state}
  end

  def set_initial_members(members, state) do
    members = Enum.map(members, &fully_qualified_name/1)

    DeltaCrdt.merge(
      crdt_name(state.name),
      Map.new(members, fn member -> {{:member, member}, 1} end),
      :infinity
    )

    Enum.each(members, fn member ->
      :ets.insert(state.members_ets_table, {member, 1})
    end)

    neighbours =
      List.delete(members, [fully_qualified_name(state.name)])
      |> crdt_names()

    send(crdt_name(state.name), {:set_neighbours, neighbours})

    %{state | nodes: Enum.map(members, fn {_name, node} -> node end) |> MapSet.new()}
  end

  defp process_diffs(state, [diff | diffs]) do
    process_diff(state, diff)
    |> process_diffs(diffs)
  end

  defp process_diffs(state, []), do: state

  defp process_diff(state, {:add, {:member, member}, 1}) do
    new_members = MapSet.put(state.members, member)

    :ets.insert(state.members_ets_table, {member, 1})

    neighbours =
      MapSet.delete(new_members, fully_qualified_name(state.name))
      |> crdt_names()

    send(crdt_name(state.name), {:set_neighbours, neighbours})

    new_nodes = Enum.map(new_members, fn {_name, node} -> node end) |> MapSet.new()

    %{state | members: new_members, nodes: new_nodes}
  end

  defp process_diff(state, {:remove, {:member, member}}) do
    :ets.match_delete(state.members_ets_table, {member, 1})

    new_members = MapSet.delete(state.members, member)
    new_nodes = Enum.map(new_members, fn {_name, node} -> node end) |> MapSet.new()

    %{state | members: new_members, nodes: new_nodes}
  end

  defp process_diff(state, {:remove, {:registry, key}}) do
    :ets.delete(state.name, key)

    state
  end

  defp process_diff(state, {:add, {:key, key}, {member, pid, value}}) do
    case :ets.lookup(state.keys_ets_table, key) do
      [{^key, _member, {other_pid, other_value}}] when other_pid != pid ->
        case resolve_key_conflict(state, key, member, pid, value, other_pid, other_value) do
          :inserted ->
            link_local_pid(pid)

            for listener <- state.listeners do
              send(listener, {:register, state.name, key, pid, value})
            end

          :dropped ->
            :ok
        end

      _ ->
        link_local_pid(pid)
        insert_key(state, key, member, pid, value)

        for listener <- state.listeners do
          send(listener, {:register, state.name, key, pid, value})
        end
    end

    state
  end

  # Two processes claim the same key. Entries that are not alive never evict
  # a live holder; a live process takes over silently (cleaning the pids
  # entry + notifying listeners) and purges the dead dots globally so
  # survivors blocked by LWW (dead timestamp larger after VM restart) flip
  # to the live value. Only a genuine conflict between two live processes
  # kills the incumbent. Dead with no live contender anywhere is retained
  # (hidden from lookup) — no deletion without a live holder for that key.
  defp resolve_key_conflict(state, key, member, pid, value, other_pid, other_value) do
    case {process_alive?(pid), process_alive?(other_pid)} do
      {true, true} ->
        unregister_local(state, key, other_pid)
        Process.exit(other_pid, {:name_conflict, {key, other_value}, state.name, pid})
        insert_key(state, key, member, pid, value)
        :inserted

      {true, false} ->
        unregister_local(state, key, other_pid)
        insert_key(state, key, member, pid, value)
        # Purge the dead dots that outranked the live value in LWW.
        # Survivors holding only the dead entry flip to the live value
        # (or empty, then live via re-put below). The purge also wipes the
        # live dots known locally as a side effect; the holder defends via
        # re-put on remove.
        DeltaCrdt.drop(crdt_name(state.name), [{:key, key}], :infinity)
        :inserted

      {false, true} ->
        # Incoming dead for a key I hold live (e.g. stale larger timestamp
        # arriving after restart). Keep the live locally and purge the dead
        # dots globally so survivors flip to live. No ETS change, no notify.
        DeltaCrdt.drop(crdt_name(state.name), [{:key, key}], :infinity)
        :dropped

      {false, _} ->
        :dropped
    end
  end

  defp insert_key(state, key, member, pid, value) do
    add_key_to_pids_table(state, pid, key)
    :ets.insert(state.keys_ets_table, {key, member, {pid, value}})
  end

  defp process_diff(state, {:remove, {:key, key}}) do
    with [{^key, member, {pid, value}}] <- :ets.lookup(state.keys_ets_table, key),
         true <- node(pid) == node(),
         true <- member == fully_qualified_name(state.name),
         true <- Process.alive?(pid) do
      # I am the holder registry and live holder but CRDT says empty
      # (e.g. a peer's cleanup drop wiped my dots as a side effect). Defend
      # by re-putting. Voluntary unregister/exit already cleared local ETS
      # synchronously, so they fall through to delete. Replicas (different
      # member) always delete, even if pid happens to be local-alive in
      # same-VM multi-registry tests.
      DeltaCrdt.put(
        crdt_name(state.name),
        {:key, key},
        {member, pid, value},
        :infinity
      )
    else
      _ -> unregister_local(state, key)
    end

    state
  end

  defp process_diff(state, {:add, {:registry, key}, value}) do
    :ets.insert(state.registry_ets_table, {key, value})
    state
  end

  defp add_key_to_pids_table(state, pid, key) do
    case :ets.lookup(state.pids_ets_table, pid) do
      [] ->
        :ets.insert(state.pids_ets_table, {pid, [key]})

      [{^pid, keys}] ->
        :ets.insert(state.pids_ets_table, {pid, Enum.uniq([key | keys])})
    end
  end

  defp remove_key_from_pids_table(state, pid, key) do
    case :ets.lookup(state.pids_ets_table, pid) do
      [] ->
        :ok

      [{^pid, keys}] ->
        case List.delete(keys, key) do
          [] ->
            :ets.match_delete(state.pids_ets_table, {pid, :_})

          new_keys ->
            :ets.insert(state.pids_ets_table, {pid, new_keys})
        end
    end
  end

  defp link_local_pid(pid) when node(pid) == node() do
    Process.link(pid)
  end

  defp link_local_pid(_pid), do: nil

  defp process_alive?(pid) do
    Horde.ClusterTransport.Erlang.process_alive?(pid)
  end

  def handle_call({:set_members, members}, _from, state) do
    new_members = MapSet.new(member_names(members))

    removed_members = MapSet.difference(state.members, new_members)
    added_members = MapSet.difference(new_members, state.members)

    DeltaCrdt.drop(
      crdt_name(state.name),
      Enum.map(removed_members, fn removed_member -> {:member, removed_member} end),
      :infinity
    )

    DeltaCrdt.merge(
      crdt_name(state.name),
      Map.new(added_members, fn added_member -> {{:member, added_member}, 1} end),
      :infinity
    )

    neighbours =
      MapSet.delete(new_members, fully_qualified_name(state.name))
      |> crdt_names()

    send(crdt_name(state.name), {:set_neighbours, neighbours})

    {:reply, :ok, %{state | members: new_members}}
  end

  def handle_call({:register, key, value, pid}, _from, state) do
    Process.link(pid)

    DeltaCrdt.put(
      crdt_name(state.name),
      {:key, key},
      {fully_qualified_name(state.name), pid, value},
      :infinity
    )

    {:reply, {:ok, self()}, state}
  end

  def handle_call({:update_value, key, pid, value}, _from, state) do
    DeltaCrdt.put(
      crdt_name(state.name),
      {:key, key},
      {fully_qualified_name(state.name), pid, value},
      :infinity
    )

    :ets.insert(state.keys_ets_table, {key, fully_qualified_name(state.name), {pid, value}})

    {:reply, :ok, state}
  end

  def handle_call({:unregister, key, _pid}, _from, state) do
    DeltaCrdt.delete(crdt_name(state.name), {:key, key}, :infinity)

    unregister_local(state, key)

    {:reply, :ok, state}
  end

  def handle_call({:delete_meta, key}, _from, state) do
    DeltaCrdt.delete(crdt_name(state.name), {:registry, key}, :infinity)

    :ets.delete(state.name, key)

    {:reply, :ok, state}
  end

  def handle_call({:put_meta, key, value}, _from, state) do
    put_meta(state, key, value)

    {:reply, :ok, state}
  end

  def handle_call(:members, _from, state) do
    {:reply, MapSet.to_list(state.members), state}
  end

  defp unregister_local(state, key) do
    case :ets.lookup(state.keys_ets_table, key) do
      [] ->
        nil

      [{key, _member, {pid, _val}}] ->
        remove_key_from_pids_table(state, pid, key)

        for listener <- state.listeners do
          send(listener, {:unregister, state.name, key, pid})
        end
    end

    :ets.match_delete(state.keys_ets_table, {key, :_, :_})
  end

  defp unregister_local(state, key, pid) do
    remove_key_from_pids_table(state, pid, key)

    for listener <- state.listeners do
      send(listener, {:unregister, state.name, key, pid})
    end

    :ets.match_delete(state.keys_ets_table, {key, :_, {pid, :_}})
  end

  defp member_names(names) do
    Enum.map(names, fn
      {name, node} -> {name, node}
      name when is_atom(name) -> {name, node()}
    end)
  end

  defp crdt_names(names) do
    Enum.map(names, fn {name, node} -> {crdt_name(name), node} end)
  end

  defp crdt_name(name), do: :"#{name}.Crdt"

  defp fully_qualified_name({name, node}) when is_atom(name) and is_atom(node), do: {name, node}
  defp fully_qualified_name(name) when is_atom(name), do: {name, node()}

  defp put_meta(state, key, value) do
    DeltaCrdt.put(crdt_name(state.name), {:registry, key}, value, :infinity)

    :ets.insert(state.registry_ets_table, {key, value})
  end
end
