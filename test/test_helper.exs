{:ok, _pid} = HordeTest.Repo.start_link()

Logger.configure(level: :info)

ExUnit.start()
