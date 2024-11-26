defmodule HordeBench.MixProject do
  use Mix.Project

  def project do
    [
      app: :horde_bench,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:benchee, "> 0.0.0"},
      {:horde, "> 0.0.0"},
      {:horde_pro, path: "~/Code/horde_pro"}
    ]
  end
end
