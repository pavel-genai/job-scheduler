defmodule Scheduler.Router do
  @moduledoc """
  Plug-based HTTP router providing the job scheduler dashboard API.

  Endpoints:
  - POST   /jobs      - Create a new job
  - GET    /jobs      - List all jobs
  - GET    /jobs/:id  - Get a specific job
  - DELETE /jobs/:id  - Delete a job
  - GET    /status    - System status overview
  """

  use Plug.Router

  plug(Plug.Logger)
  plug(:match)
  plug(Plug.Parsers, parsers: [:json], json_decoder: Jason)
  plug(:dispatch)

  # POST /jobs - Create a new job
  post "/jobs" do
    attrs = conn.body_params
    job = Scheduler.Job.new(attrs)

    # Validate DAG
    existing_jobs = Scheduler.Store.all()

    case Scheduler.DAG.validate_no_cycle(job.id, job.deps, Scheduler.DAG.build_graph(existing_jobs)) do
      :ok ->
        # Validate cron if provided
        cron_valid =
          if job.cron do
            case Scheduler.Cron.parse(job.cron) do
              {:ok, _} -> true
              {:error, _} -> false
            end
          else
            true
          end

        if cron_valid do
          Scheduler.Store.put(job)
          Scheduler.Runner.maybe_run_ready_jobs()
          send_json(conn, 201, %{ok: true, job: job})
        else
          send_json(conn, 400, %{error: "Invalid cron expression: #{job.cron}"})
        end

      {:error, reason} ->
        send_json(conn, 400, %{error: reason})
    end
  end

  # GET /jobs - List all jobs
  get "/jobs" do
    jobs = Scheduler.Store.all()
    send_json(conn, 200, %{jobs: jobs, count: length(jobs)})
  end

  # GET /jobs/:id - Get a specific job
  get "/jobs/:id" do
    case Scheduler.Store.get(id) do
      {:ok, job} ->
        send_json(conn, 200, %{job: job})

      {:error, :not_found} ->
        send_json(conn, 404, %{error: "Job not found"})
    end
  end

  # DELETE /jobs/:id - Delete a job
  delete "/jobs/:id" do
    case Scheduler.Store.delete(id) do
      :ok ->
        send_json(conn, 200, %{ok: true, message: "Job #{id} deleted"})

      {:error, :not_found} ->
        send_json(conn, 404, %{error: "Job not found"})
    end
  end

  # GET /status - System status
  get "/status" do
    counts = Scheduler.Store.status_counts()
    total = Scheduler.Store.all() |> length()

    status = %{
      status: "running",
      total_jobs: total,
      job_counts: counts,
      uptime_seconds: System.monotonic_time(:second)
    }

    send_json(conn, 200, status)
  end

  match _ do
    send_json(conn, 404, %{error: "Not found"})
  end

  defp send_json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end
end
