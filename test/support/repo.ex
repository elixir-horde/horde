defmodule HordeTest.Repo do
  use Ecto.Repo,
    otp_app: :horde,
    adapter: Ecto.Adapters.Postgres

  def init(_context, config) do
    {:ok, Keyword.put(config, :url, System.get_env("POSTGRES_URL"))}
  end
end
