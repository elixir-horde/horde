default: watch

docker:
  docker-compose up -d

bench_insert:
  watchexec -r --clear=reset -w . --project-origin=. --workdir=benchmarks --stop-timeout=0 mix run dynamic_supervisor_insert.exs

bench_registry:
  watchexec -r --clear=reset -w . --project-origin=. --workdir=benchmarks --stop-timeout=0 mix run registry_replication.exs

bench_dynamic_supervisor:
  watchexec -r --clear=reset -w . --project-origin=. --workdir=benchmarks --stop-timeout=0 mix run dynamic_supervisor_recovery.exs

watch:
  watchexec -r --clear=reset -w . --project-origin=. --stop-timeout=0 mix test --warnings-as-errors --all-warnings

watch2:
  watchexec -r --clear=reset -w . --project-origin=. --stop-timeout=0 mix test --warnings-as-errors --all-warnings test/horde/registry_test.exs

watch3:
  watchexec -r --clear=reset -w . --project-origin=. --stop-timeout=0 mix test --warnings-as-errors --all-warnings test/horde/adapter/postgres/locker_test.exs

migrate:
  MIX_ENV=test mix ecto.migrate -r HordeTest.Repo

db_reset:
  MIX_ENV=test mix do ecto.drop -r HordeTest.Repo, ecto.create -r HordeTest.Repo, ecto.migrate -r HordeTest.Repo

gen_migration MIG:
  MIX_ENV=test mix ecto.gen.migration -r HordeTest.Repo {{MIG}}
