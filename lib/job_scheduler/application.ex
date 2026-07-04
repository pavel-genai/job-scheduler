defmodule JobScheduler.Application do
  @moduledoc """
  OTP Application for the Job Scheduler.

  Starts the supervision tree with:
  - ETS Store
  - Task Supervisor for job execution
  - Job Runner
  - Cron Scheduler
  - Plug/Cowboy HTTP server
  """

  use Application

  @impl true
  def start(_type, _args) do
    port = Application.get_env(:job_scheduler, :port, 4000)

    children = [
      Scheduler.Store,
      {Task.Supervisor, name: Scheduler.TaskSupervisor},
      Scheduler.Runner,
      Scheduler.Cron,
      {Plug.Cowboy, scheme: :http, plug: Scheduler.Router, options: [port: port]}
    ]

    opts = [strategy: :one_for_one, name: JobScheduler.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
