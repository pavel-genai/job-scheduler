defmodule Scheduler.Cron do
  @moduledoc """
  Cron-based job scheduling using the Crontab library.

  Parses cron expressions and determines when jobs should next run.
  Runs as a GenServer that periodically checks for jobs that need triggering.
  """

  use GenServer

  require Logger

  @check_interval :timer.seconds(30)

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Parses a cron expression string and returns a Crontab.CronExpression.
  """
  @spec parse(String.t()) :: {:ok, Crontab.CronExpression.t()} | {:error, String.t()}
  def parse(expression) do
    case Crontab.CronExpression.Parser.parse(expression) do
      {:ok, cron} -> {:ok, cron}
      {:error, reason} -> {:error, "Invalid cron expression: #{inspect(reason)}"}
    end
  end

  @doc """
  Returns the next occurrence after the given datetime for the cron expression.
  """
  @spec next_occurrence(String.t(), NaiveDateTime.t()) ::
          {:ok, NaiveDateTime.t()} | {:error, String.t()}
  def next_occurrence(expression, from \\ NaiveDateTime.utc_now()) do
    case parse(expression) do
      {:ok, cron} ->
        case Crontab.Scheduler.get_next_run_date(cron, from) do
          {:ok, next} -> {:ok, next}
          {:error, reason} -> {:error, "Could not compute next run: #{inspect(reason)}"}
        end

      error ->
        error
    end
  end

  @doc """
  Checks if a cron expression matches the given datetime.
  """
  @spec matches?(String.t(), NaiveDateTime.t()) :: boolean()
  def matches?(expression, datetime \\ NaiveDateTime.utc_now()) do
    case parse(expression) do
      {:ok, cron} ->
        Crontab.DateChecker.matches_date?(cron, datetime)

      _ ->
        false
    end
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    schedule_check()
    {:ok, %{last_check: NaiveDateTime.utc_now()}}
  end

  @impl true
  def handle_info(:check_cron, state) do
    now = NaiveDateTime.utc_now()
    check_and_trigger_jobs(now, state.last_check)
    schedule_check()
    {:noreply, %{state | last_check: now}}
  end

  defp schedule_check do
    Process.send_after(self(), :check_cron, @check_interval)
  end

  defp check_and_trigger_jobs(now, _last_check) do
    Scheduler.Store.all()
    |> Enum.filter(fn job ->
      job.cron != nil and job.status in [:pending, :completed]
    end)
    |> Enum.each(fn job ->
      if matches?(job.cron, now) do
        Logger.info("Cron trigger for job #{job.id} (#{job.name})")

        case Scheduler.Job.transition(job, :pending) do
          {:ok, updated} ->
            Scheduler.Store.put(%{updated | attempts: 0, error: nil, result: nil})
            Scheduler.Runner.maybe_run_ready_jobs()

          _ ->
            :ok
        end
      end
    end)
  end
end
