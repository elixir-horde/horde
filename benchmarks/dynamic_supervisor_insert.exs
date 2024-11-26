defmodule HordeProTest.Repo do
  use Ecto.Repo,
    otp_app: :horde_pro,
    adapter: Ecto.Adapters.Postgres

  def init(_context, config) do
    new_config =
      config
      |> Keyword.put(:url, System.get_env("POSTGRES_URL"))
      |> Keyword.put(:pool_size, 50)

    {:ok, new_config}
  end
end

{:ok, _pid} = HordeProTest.Repo.start_link()

Logger.configure(level: :critical)

cases = %{"thousand" => 1..1000}
# parallel = %{"one" => 1, "two" => 2, "four" => 4, "eight" => 8, "sixteen" => 16}
parallel = %{"one" => 1, "eight" => 8, "sixteen" => 16, "thirtytwo" => 32}

inputs =
  Enum.flat_map(cases, fn {k1, v1} ->
    Enum.map(parallel, fn {k2, v2} ->
      {"#{k1} cases; #{k2} parallel", {v1, v2}}
    end)
  end)
  |> Map.new()

Benchee.run(
  %{
    "Ecto.Repo.insert/3" => fn {pids, {cases, parallel}} ->
      child_spec =
        Task.child_spec(fn -> :foo end)

      Task.async_stream(
        cases,
        fn n ->
          HordePro.DynamicSupervisorChild.encode(
            %{supervisor_id: "123_123", lock_id: -2_329_838},
            self(),
            child_spec.start,
            child_spec.restart,
            5000,
            :worker,
            []
          )
          |> HordeProTest.Repo.insert()
        end,
        max_concurrency: parallel
      )
      |> Stream.run()

      pids
    end,
    "Elixir.DynamicSupervisor.start_child/3" => fn {pids, {cases, parallel}} ->
      bench_pid = self()

      Task.async_stream(
        cases,
        fn n ->
          {:ok, _child_pid} =
            DynamicSupervisor.start_child(
              {:via, PartitionSupervisor, {ElixirSupervisor, n}},
              {Task,
               fn ->
                 send(bench_pid, {:msg, n})
                 Process.sleep(5000)
               end}
            )
        end,
        max_concurrency: parallel * 2
      )
      |> Stream.run()

      Enum.each(cases, fn n ->
        receive do
          {:msg, ^n} -> :ok
        after
          5000 -> raise "message not received"
        end
      end)

      pids
    end,
    "HordePro.DynamicSupervisor.start_child/3" => fn {pids, {cases, parallel}} ->
      bench_pid = self()

      Task.async_stream(
        cases,
        fn n ->
          {:ok, _child_pid} =
            HordePro.DynamicSupervisor.start_child(
              {:via, PartitionSupervisor, {HordeProSupervisor, n}},
              {Task,
               fn ->
                 send(bench_pid, {:msg, n})
                 Process.sleep(5000)
               end}
            )
        end,
        max_concurrency: parallel * 2
      )
      |> Stream.run()

      Enum.each(cases, fn n ->
        receive do
          {:msg, ^n} -> :ok
        after
          5000 -> raise "message not received"
        end
      end)

      pids
    end
  },
  inputs: inputs,
  before_each: fn {cases, parallel} ->
    ref = :rand.uniform(99_999_999_999)

    {:ok, sup1} =
      PartitionSupervisor.start_link(
        name: HordeProSupervisor,
        partitions: parallel,
        child_spec:
          HordePro.DynamicSupervisor.child_spec(
            strategy: :one_for_one,
            backend:
              HordePro.Adapter.Postgres.DynamicSupervisorBackend.new(
                repo: HordeProTest.Repo,
                supervisor_id: "benchmark_#{ref}"
              )
          )
      )

    {:ok, sup2} =
      PartitionSupervisor.start_link(
        name: ElixirSupervisor,
        partitions: parallel,
        child_spec: DynamicSupervisor.child_spec(strategy: :one_for_one)
      )

    {[sup1, sup2], {cases, parallel}}
  end,
  after_each: fn pids ->
    Enum.each(pids, fn pid ->
      Process.flag(:trap_exit, true)
      Process.exit(pid, :kill)

      receive do
        {:EXIT, ^pid, :killed} -> :ok
      after
        5000 ->
          raise "whoops!"
      end
    end)
  end
)
