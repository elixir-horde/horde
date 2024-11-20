{:ok, _pid} = HordeProTest.Repo.start_link()

Logger.configure(level: :info)

ExUnit.start()
