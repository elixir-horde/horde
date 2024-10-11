default:
  mix test

docker:
  docker-compose up -d

watch:
  find lib test | entr mix do compile --warnings-as-errors, test
