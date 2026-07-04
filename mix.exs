defmodule JobScheduler.MixProject do
  use Mix.Project

  def project do
    [
      app: :job_scheduler,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {JobScheduler.Application, []}
    ]
  end

  defp deps do
    [
      {:plug_cowboy, "~> 2.6"},
      {:jason, "~> 1.4"},
      {:crontab, "~> 1.1"}
    ]
  end
end
