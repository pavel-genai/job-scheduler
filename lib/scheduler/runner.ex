defmodule Scheduler.Runner do
  @moduledoc """
  Executes jobs as supervised Task processes with retry logic.

  Monitors running tasks and handles completion, failure, and retry transitions.
  """

  use GenServer

  require Logger

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Submits a job for execution. The job must be in :pending state
  and have all dependencies satisfied.
  """
  @spec submit(String.t()) :: :ok | {:error, term()}
  def submit(job_id) do
    GenServer.call(__MODULE__, {:submit, job_id})
  end

  @doc """
  Checks for jobs that are ready (deps satisfied) and submits them.
  """
  @spec maybe_run_ready_jobs() :: :ok
  def maybe_run_ready_jobs do
    GenServer.cast(__MODULE__, :run_ready)
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    {:ok, %{tasks: %{}}}
  end

  @impl true
  def handle_call({:submit, job_id}, _from, state) do
    case Scheduler.Store.get(job_id) do
      {:ok, job} when job.status in [:pending, :retrying] ->
        {task_ref, new_state} = start_job(job, state)

        if task_ref do
          {:reply, :ok, new_state}
        else
          {:reply, {:error, :failed_to_start}, state}
        end

      {:ok, job} ->
        {:reply, {:error, {:invalid_status, job.status}}, state}

      {:error, :not_found} ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_cast(:run_ready, state) do
    jobs = Scheduler.Store.all()
    ready_ids = Scheduler.DAG.ready_jobs(jobs)

    new_state =
      Enum.reduce(ready_ids, state, fn job_id, acc ->
        case Scheduler.Store.get(job_id) do
          {:ok, job} when job.status == :pending ->
            {_ref, updated_state} = start_job(job, acc)
            updated_state

          _ ->
            acc
        end
      end)

    {:noreply, new_state}
  end

  @impl true
  def handle_info({ref, result}, state) when is_reference(ref) do
    # Task completed successfully
    Process.demonitor(ref, [:flush])

    case Map.pop(state.tasks, ref) do
      {job_id, tasks} when job_id != nil ->
        handle_job_success(job_id, result)
        {:noreply, %{state | tasks: tasks}}

      {nil, _} ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
    case Map.pop(state.tasks, ref) do
      {job_id, tasks} when job_id != nil ->
        handle_job_failure(job_id, reason)
        {:noreply, %{state | tasks: tasks}}

      {nil, _} ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # Private functions

  defp start_job(job, state) do
    Logger.info("Starting job #{job.id} (#{job.name}), attempt #{job.attempts + 1}")

    case Scheduler.Job.transition(job, :running) do
      {:ok, running_job} ->
        running_job = %{running_job | attempts: running_job.attempts + 1}
        Scheduler.Store.put(running_job)

        task =
          Task.Supervisor.async_nolink(Scheduler.TaskSupervisor, fn ->
            execute_job(running_job)
          end)

        Scheduler.Store.put(%{running_job | task_ref: task.ref})
        {task.ref, %{state | tasks: Map.put(state.tasks, task.ref, job.id)}}

      {:error, reason} ->
        Logger.error("Failed to start job #{job.id}: #{reason}")
        {nil, state}
    end
  end

  defp execute_job(%Scheduler.Job{module: nil}), do: :ok
  defp execute_job(%Scheduler.Job{function: nil}), do: :ok

  defp execute_job(%Scheduler.Job{module: mod_str, function: fun_str, args: args}) do
    module = String.to_existing_atom("Elixir.#{mod_str}")
    function = String.to_existing_atom(fun_str)
    apply(module, function, args || [])
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp handle_job_success(job_id, result) do
    case Scheduler.Store.get(job_id) do
      {:ok, job} ->
        case Scheduler.Job.transition(job, :completed) do
          {:ok, completed} ->
            Scheduler.Store.put(%{completed | result: inspect(result)})
            Logger.info("Job #{job_id} completed successfully")
            # Trigger downstream jobs
            maybe_run_ready_jobs()

          {:error, reason} ->
            Logger.error("Failed to transition job #{job_id} to completed: #{reason}")
        end

      _ ->
        :ok
    end
  end

  defp handle_job_failure(job_id, reason) do
    case Scheduler.Store.get(job_id) do
      {:ok, job} ->
        if job.attempts < job.max_retries do
          Logger.warning(
            "Job #{job_id} failed (attempt #{job.attempts}/#{job.max_retries}), retrying..."
          )

          case Scheduler.Job.transition(job, :retrying) do
            {:ok, retrying} ->
              Scheduler.Store.put(%{retrying | error: inspect(reason)})
              backoff = job.backoff_ms * job.attempts
              Process.send_after(__MODULE__, {:retry, job_id}, backoff)

            {:error, _} ->
              mark_failed(job, reason)
          end
        else
          Logger.error("Job #{job_id} failed after #{job.attempts} attempts")
          mark_failed(job, reason)
        end

      _ ->
        :ok
    end
  end

  defp mark_failed(job, reason) do
    case Scheduler.Job.transition(job, :failed) do
      {:ok, failed} ->
        Scheduler.Store.put(%{failed | error: inspect(reason)})

      {:error, _} ->
        Scheduler.Store.put(%{job | status: :failed, error: inspect(reason)})
    end
  end

  @impl true
  def handle_info({:retry, job_id}, state) do
    case Scheduler.Store.get(job_id) do
      {:ok, job} when job.status == :retrying ->
        {_ref, new_state} = start_job(job, state)
        {:noreply, new_state}

      _ ->
        {:noreply, state}
    end
  end
end
