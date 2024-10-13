default: watch

docker:
  docker-compose up -d

watch:
  watchexec -r --clear=reset --project-origin=. --stop-timeout=0 MIX_ENV=test mix do compile --warnings-as-errors, test

migrate:
  mix ecto.migrate -r HordeProTest.Repo

gen_migration MIG:
  mix ecto.gen.migration -r HordeProTest.Repo {{MIG}}
