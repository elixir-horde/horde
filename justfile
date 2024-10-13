default: watch

docker:
  docker-compose up -d

watch:
  watchexec -r --clear=reset --project-origin=. --stop-timeout=0 MIX_ENV=test mix do compile --warnings-as-errors, test

migrate:
  MIX_ENV=test mix ecto.migrate -r HordeProTest.Repo

gen_migration MIG:
  MIX_ENV=test mix ecto.gen.migration -r HordeProTest.Repo {{MIG}}
