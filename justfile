default: watch

docker:
  docker-compose up -d

bench:
  MIX_ENV=dev mix run benchmarks/horde_pro_dynamic_supervisor.exs

watch:
  watchexec -r --clear=reset --project-origin=. --stop-timeout=0 MIX_ENV=test mix do compile --warnings-as-errors, test

migrate:
  MIX_ENV=test mix ecto.migrate -r HordeProTest.Repo

db_reset:
  MIX_ENV=test mix do ecto.drop -r HordeProTest.Repo, ecto.create -r HordeProTest.Repo, ecto.migrate -r HordeProTest.Repo

gen_migration MIG:
  MIX_ENV=test mix ecto.gen.migration -r HordeProTest.Repo {{MIG}}
