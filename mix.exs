defmodule TasRinhaback3ed.MixProject do
  use Mix.Project

  def project do
    [
      app: :tas_rinhaback_3ed,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {TasRinhaback3ed.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:plug, "~> 1.15"},
      {:bandit, "~> 1.5"},
      {:jason, "~> 1.4"},
      {:decimal, "~> 2.1"},
      {:req, "~> 0.5.0"},
      {:ecto_sql, "~> 3.11"},
      {:postgrex, ">= 0.0.0"},
      {:bypass, "~> 2.1", only: :test}
    ]
  end
end
