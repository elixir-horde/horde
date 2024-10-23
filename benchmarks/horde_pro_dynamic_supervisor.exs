defmodule HordeProTest.Repo do
  use Ecto.Repo,
    otp_app: :horde_pro,
    adapter: Ecto.Adapters.Postgres

  def init(_context, config) do
    {:ok, Keyword.put(config, :url, System.get_env("POSTGRES_URL"))}
  end
end

{:ok, _pid} = HordeProTest.Repo.start_link()

Logger.configure(level: :info)

Benchee.run(
  %{
    "start_child/3 with PartitionSupervisor" => fn cases ->
      ref = :rand.uniform(99_999_999_999)
      name = MyPartitionSupervisor

      {:ok, sup} =
        PartitionSupervisor.start_link(
          name: name,
          partitions: 20,
          child_spec:
            HordePro.DynamicSupervisor.child_spec(
              strategy: :one_for_one,
              backend:
                HordePro.Adapter.Postgres.SupervisorBackend.new(
                  repo: HordeProTest.Repo,
                  supervisor_id: "benchmark_#{ref}"
                )
            )
        )

      bench_pid = self()

      cases
      |> Task.async_stream(
        fn n ->
          {:ok, _child_pid} =
            HordePro.DynamicSupervisor.start_child(
              {:via, PartitionSupervisor, {name, n}},
              {Task,
               fn ->
                 send(bench_pid, {:msg, n})
                 Process.sleep(5000)
               end}
            )
        end,
        max_concurrency: 20
      )
      |> Stream.run()

      cases
      |> Enum.each(fn n ->
        receive do
          {:msg, ^n} -> :ok
        after
          5000 -> raise "message not received"
        end
      end)

      Process.flag(:trap_exit, true)
      Process.exit(sup, :kill)

      receive do
        {:EXIT, ^sup, :killed} -> :ok
      after
        5000 ->
          raise "whoops!"
      end
    end,
    "start_child/3" => fn cases ->
      ref = :rand.uniform(99_999_999_999)

      {:ok, sup} =
        HordePro.DynamicSupervisor.start_link(
          strategy: :one_for_one,
          backend:
            HordePro.Adapter.Postgres.SupervisorBackend.new(
              repo: HordeProTest.Repo,
              supervisor_id: "benchmark_#{ref}"
            )
        )

      cases
      |> Enum.each(fn _n ->
        {:ok, _child_pid} =
          HordePro.DynamicSupervisor.start_child(
            sup,
            {Task,
             fn ->
               1 / 1000
               Process.sleep(5000)
             end}
          )
      end)

      Process.flag(:trap_exit, true)
      Process.exit(sup, :kill)

      receive do
        {:EXIT, ^sup, :killed} -> :ok
      after
        5000 ->
          raise "whoops!"
      end
    end
  },
  inputs: %{"thousand" => 1..1000}
)
