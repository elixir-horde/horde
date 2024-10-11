defmodule HordeProTest.Repo do
  use Ecto.Repo,
    otp_app: :horde_pro,
    adapter: Ecto.Adapters.Postgres

  def init(_context, _config) do
    {:ok, url: System.get_env("POSTGRES_URL")}
  end
end
