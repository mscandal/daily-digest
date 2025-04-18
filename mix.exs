defmodule DailyDigest.MixProject do
  use Mix.Project

  def project do
    [
      app: :daily_digest,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      mod: {DailyDigest, []},
      extra_applications: [:logger, :inets]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:bupe, "~> 0.6"},
      {:slugify, "~> 1.3.1"},
      {:floki, "~> 0.37.0"},
      {:timex, "~> 3.0"},
      {:crontab, "~> 1.1"},
      {:logger_file_backend, "~> 0.0.14"}
    ]
  end
end
