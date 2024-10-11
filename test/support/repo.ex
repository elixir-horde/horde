defmodule HordeProTest.Repo do
  use Ecto.Repo,
    otp_app: :horde_pro,
    adapter: Ecto.Adapters.Postgres

  def init(_context, _config) do
    {:ok, url: "ecto://postgres:postgres@localhost:6431/horde_pro"}
  end
end
