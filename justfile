default:
  mix test

docker:
  docker-compose up -d

watch:
  find lib test | MIX_ENV=test entr mix do compile --warnings-as-errors, test

migrate:
  mix ecto.migrate -r HordeProTest.Repo

gen_migration MIG:
  mix ecto.gen.migration -r HordeProTest.Repo {{MIG}}
