defmodule HordeTest.Repo do
  use Ecto.Repo,
    otp_app: :horde,
    adapter: Ecto.Adapters.Postgres

  def init(_context, config) do
    new_config =
      config
      |> Keyword.put(:url, System.get_env("POSTGRES_URL"))
      |> Keyword.put(:pool_size, 50)

    {:ok, new_config}
  end
end

{:ok, _pid} = HordeTest.Repo.start_link()

defmodule HordeTest.Telemetry do
  def handle_event([:horde_test, :repo, :query], measurements, metadata, config) do
    IO.inspect(metadata, label: "METADATA")

    measurements
    |> Map.new(fn {label, meas} ->
      {label, :erlang.convert_time_unit(meas, :native, :microsecond) / 1000}
    end)
    |> IO.inspect(label: "QUERY MEASUREMENTS")
  end
end

tel_attach = fn ->
  :ok =
    :telemetry.attach(
      "foo",
      [:horde_test, :repo, :query],
      &HordeTest.Telemetry.handle_event/4,
      %{}
    )
end

# tel_attach.()

# Logger.configure(level: :critical)
Logger.configure(level: :error)

# cases = %{"thousand" => 1..1000}
cases = %{"hundred" => 1..100, "ten" => 1..10, "five hundred" => 1..500}
# parallel = %{"one" => 1, "two" => 2, "four" => 4, "eight" => 8, "sixteen" => 16}
# parallel = %{"one" => 1, "eight" => 8, "thirtytwo" => 32}
parallel = %{"eight" => 8}

inputs =
  Enum.flat_map(cases, fn {k1, v1} ->
    Enum.map(parallel, fn {k2, v2} ->
      {"#{k1} cases; #{k2} parallel", {v1, v2}}
    end)
  end)
  |> Map.new()

import MyBench

Benchee.run(
  %{
    "Horde.Registry replication" => fn {pids, {cases, _parallel}} ->
      Enum.each(cases, fn n ->
        Task.start_link(fn ->
          Horde.Registry.register(HordeRegistry, "hello_#{n}", :value)
          Process.sleep(20_000)
        end)
      end)

      last = Enum.max(cases)

      while(fn ->
        Process.sleep(2)
        last != Horde.Registry.count(HordeRegistry2)
      end)

      pids
    end,
    "Horde.Registry replication" => fn {pids, {cases, _parallel}} ->
      Enum.each(cases, fn n ->
        Task.start_link(fn ->
          Horde.Registry.register(HordeRegistry, "hello_#{n}", :value)
          Process.sleep(20_000)
        end)
      end)

      last = Enum.max(cases)

      while(fn ->
        Process.sleep(2)

        last != Horde.Registry.count(HordeRegistry2)
      end)

      pids
    end

    # "Ecto.Repo.insert/3" => fn {pids, {cases, parallel}} ->
    #   child_spec =
    #     Task.child_spec(fn -> :foo end)

    #   Task.async_stream(
    #     cases,
    #     fn n ->
    #       Horde.DynamicSupervisorChild.encode(
    #         %{supervisor_id: "123_123", lock_id: -2_329_838},
    #         self(),
    #         child_spec.start,
    #         child_spec.restart,
    #         5000,
    #         :worker,
    #         []
    #       )
    #       |> HordeTest.Repo.insert()
    #     end,
    #     max_concurrency: parallel
    #   )
    #   |> Stream.run()

    #   pids
    # end,
    # "Elixir.DynamicSupervisor.start_child/3" => fn {pids, {cases, parallel}} ->
    #   bench_pid = self()

    #   Task.async_stream(
    #     cases,
    #     fn n ->
    #       {:ok, _child_pid} =
    #         DynamicSupervisor.start_child(
    #           {:via, PartitionSupervisor, {ElixirSupervisor, n}},
    #           {Task,
    #            fn ->
    #              send(bench_pid, {:msg, n})
    #              Process.sleep(5000)
    #            end}
    #         )
    #     end,
    #     max_concurrency: parallel * 2
    #   )
    #   |> Stream.run()

    #   Enum.each(cases, fn n ->
    #     receive do
    #       {:msg, ^n} -> :ok
    #     after
    #       5000 -> raise "message not received"
    #     end
    #   end)

    #   pids
    # end,
    # "Horde.DynamicSupervisor.start_child/3" => fn {pids, {cases, parallel}} ->
    #   bench_pid = self()

    #   Task.async_stream(
    #     cases,
    #     fn n ->
    #       {:ok, _child_pid} =
    #         Horde.DynamicSupervisor.start_child(
    #           {:via, PartitionSupervisor, {HordeSupervisor, n}},
    #           {Task,
    #            fn ->
    #              send(bench_pid, {:msg, n})
    #              Process.sleep(5000)
    #            end}
    #         )
    #     end,
    #     max_concurrency: parallel * 2
    #   )
    #   |> Stream.run()

    #   Enum.each(cases, fn n ->
    #     receive do
    #       {:msg, ^n} -> :ok
    #     after
    #       5000 -> raise "message not received"
    #     end
    #   end)

    #   pids
    # end
  },
  inputs: inputs,
  before_each: fn {cases, parallel} ->
    ref = :rand.uniform(99_999_999_999)

    {:ok, reg2} =
      Horde.Registry.start_link(
        name: HordeRegistry,
        keys: :unique,
        delta_crdt_options: [sync_interval: 20]
      )

    {:ok, reg2_2} =
      Horde.Registry.start_link(
        name: HordeRegistry2,
        keys: :unique,
        delta_crdt_options: [sync_interval: 20]
      )

    Horde.Cluster.set_members(HordeRegistry, [HordeRegistry, HordeRegistry2])

    {:ok, reg1} =
      Horde.Registry.start_link(
        name: HordeRegistry,
        keys: :unique,
        backend:
          Horde.Adapter.Postgres.RegistryBackend.new(
            repo: HordeTest.Repo,
            registry_id: "registry_#{ref}"
          ),
        partitions: parallel
      )

    {:ok, reg1_2} =
      Horde.Registry.start_link(
        name: HordeRegistry2,
        keys: :unique,
        backend:
          Horde.Adapter.Postgres.RegistryBackend.new(
            repo: HordeTest.Repo,
            registry_id: "registry_#{ref}"
          ),
        partitions: parallel
      )

    {:ok, reg3} =
      Registry.start_link(
        name: ElixirRegistry,
        keys: :unique,
        partitions: parallel
      )

    {[reg1, reg1_2, reg2, reg2_2, reg3], {cases, parallel}}
  end,
  after_each: fn pids ->
    Enum.each(pids, fn pid ->
      Process.flag(:trap_exit, true)
      Process.exit(pid, :shutdown)

      receive do
        {:EXIT, ^pid, _reason} -> :ok
      after
        5000 ->
          raise "whoops!"
      end
    end)
  end
)
