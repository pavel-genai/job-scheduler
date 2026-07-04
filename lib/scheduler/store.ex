defmodule Scheduler.Store do
  @moduledoc """
  ETS-backed storage for job state.

  Provides CRUD operations and query functions for jobs stored in an ETS table.
  Runs as a GenServer to own the ETS table.
  """

  use GenServer

  @table :job_scheduler_store

  # Client API

  @doc """
  Starts the store GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Inserts or updates a job in the store.
  """
  @spec put(Scheduler.Job.t()) :: :ok
  def put(%Scheduler.Job{} = job) do
    :ets.insert(@table, {job.id, job})
    :ok
  end

  @doc """
  Retrieves a job by ID.
  """
  @spec get(String.t()) :: {:ok, Scheduler.Job.t()} | {:error, :not_found}
  def get(id) do
    case :ets.lookup(@table, id) do
      [{^id, job}] -> {:ok, job}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Returns all jobs.
  """
  @spec all() :: [Scheduler.Job.t()]
  def all do
    :ets.tab2list(@table)
    |> Enum.map(fn {_id, job} -> job end)
  end

  @doc """
  Deletes a job by ID.
  """
  @spec delete(String.t()) :: :ok | {:error, :not_found}
  def delete(id) do
    case :ets.lookup(@table, id) do
      [{^id, _}] ->
        :ets.delete(@table, id)
        :ok

      [] ->
        {:error, :not_found}
    end
  end

  @doc """
  Returns jobs filtered by status.
  """
  @spec by_status(atom()) :: [Scheduler.Job.t()]
  def by_status(status) do
    all() |> Enum.filter(&(&1.status == status))
  end

  @doc """
  Returns the count of jobs grouped by status.
  """
  @spec status_counts() :: map()
  def status_counts do
    all()
    |> Enum.group_by(& &1.status)
    |> Enum.map(fn {status, jobs} -> {status, length(jobs)} end)
    |> Map.new()
  end

  @doc """
  Updates a job by applying a function to it.
  """
  @spec update(String.t(), (Scheduler.Job.t() -> Scheduler.Job.t())) ::
          {:ok, Scheduler.Job.t()} | {:error, :not_found}
  def update(id, fun) when is_function(fun, 1) do
    case get(id) do
      {:ok, job} ->
        updated = fun.(job)
        put(updated)
        {:ok, updated}

      error ->
        error
    end
  end

  @doc """
  Clears all jobs from the store.
  """
  @spec clear() :: :ok
  def clear do
    :ets.delete_all_objects(@table)
    :ok
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    table = :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])
    {:ok, %{table: table}}
  end
end
