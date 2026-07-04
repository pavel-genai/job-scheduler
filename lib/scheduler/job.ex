defmodule Scheduler.Job do
  @moduledoc """
  Defines the Job struct and state transitions.

  A job has the following states:
  - :pending   - waiting for dependencies or scheduling
  - :running   - currently executing
  - :completed - finished successfully
  - :failed    - exhausted all retries
  - :retrying  - failed but will be retried
  """

  @valid_states [:pending, :running, :completed, :failed, :retrying]

  @derive {Jason.Encoder,
           only: [
             :id,
             :name,
             :module,
             :function,
             :args,
             :deps,
             :status,
             :retry_policy,
             :cron,
             :attempts,
             :max_retries,
             :backoff_ms,
             :result,
             :error,
             :created_at,
             :updated_at,
             :started_at,
             :completed_at
           ]}

  defstruct [
    :id,
    :name,
    :module,
    :function,
    :args,
    :deps,
    :status,
    :retry_policy,
    :cron,
    :attempts,
    :max_retries,
    :backoff_ms,
    :result,
    :error,
    :created_at,
    :updated_at,
    :started_at,
    :completed_at,
    :task_ref
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          module: String.t() | nil,
          function: String.t() | nil,
          args: list() | nil,
          deps: [String.t()],
          status: atom(),
          retry_policy: map() | nil,
          cron: String.t() | nil,
          attempts: non_neg_integer(),
          max_retries: non_neg_integer(),
          backoff_ms: non_neg_integer(),
          result: any(),
          error: any(),
          created_at: DateTime.t(),
          updated_at: DateTime.t(),
          started_at: DateTime.t() | nil,
          completed_at: DateTime.t() | nil,
          task_ref: reference() | nil
        }

  @doc """
  Creates a new job from a map of attributes.
  """
  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    now = DateTime.utc_now()
    retry_policy = Map.get(attrs, "retry_policy") || Map.get(attrs, :retry_policy) || %{}

    %__MODULE__{
      id: Map.get(attrs, "id") || Map.get(attrs, :id) || generate_id(),
      name: Map.get(attrs, "name") || Map.get(attrs, :name) || "unnamed",
      module: Map.get(attrs, "module") || Map.get(attrs, :module),
      function: Map.get(attrs, "function") || Map.get(attrs, :function),
      args: Map.get(attrs, "args") || Map.get(attrs, :args) || [],
      deps: Map.get(attrs, "deps") || Map.get(attrs, :deps) || [],
      status: :pending,
      cron: Map.get(attrs, "cron") || Map.get(attrs, :cron),
      retry_policy: retry_policy,
      attempts: 0,
      max_retries: get_max_retries(retry_policy),
      backoff_ms: get_backoff_ms(retry_policy),
      result: nil,
      error: nil,
      created_at: now,
      updated_at: now,
      started_at: nil,
      completed_at: nil,
      task_ref: nil
    }
  end

  @doc """
  Returns the list of valid job states.
  """
  @spec valid_states() :: [atom()]
  def valid_states, do: @valid_states

  @doc """
  Transitions a job to a new state with validation.
  """
  @spec transition(t(), atom()) :: {:ok, t()} | {:error, String.t()}
  def transition(%__MODULE__{} = job, new_status) when new_status in @valid_states do
    if valid_transition?(job.status, new_status) do
      now = DateTime.utc_now()

      updated =
        %{job | status: new_status, updated_at: now}
        |> maybe_set_started(new_status)
        |> maybe_set_completed(new_status)

      {:ok, updated}
    else
      {:error, "Invalid transition from #{job.status} to #{new_status}"}
    end
  end

  def transition(_job, invalid_status) do
    {:error, "Invalid status: #{inspect(invalid_status)}"}
  end

  defp valid_transition?(:pending, :running), do: true
  defp valid_transition?(:pending, :failed), do: true
  defp valid_transition?(:running, :completed), do: true
  defp valid_transition?(:running, :failed), do: true
  defp valid_transition?(:running, :retrying), do: true
  defp valid_transition?(:retrying, :running), do: true
  defp valid_transition?(:retrying, :failed), do: true
  defp valid_transition?(:failed, :pending), do: true
  defp valid_transition?(:completed, :pending), do: true
  defp valid_transition?(_, _), do: false

  defp maybe_set_started(job, :running), do: %{job | started_at: DateTime.utc_now()}
  defp maybe_set_started(job, _), do: job

  defp maybe_set_completed(job, :completed), do: %{job | completed_at: DateTime.utc_now()}
  defp maybe_set_completed(job, :failed), do: %{job | completed_at: DateTime.utc_now()}
  defp maybe_set_completed(job, _), do: job

  defp generate_id do
    :crypto.strong_rand_bytes(8) |> Base.hex_encode32(case: :lower, padding: false)
  end

  defp get_max_retries(%{"max_retries" => n}) when is_integer(n), do: n
  defp get_max_retries(%{max_retries: n}) when is_integer(n), do: n
  defp get_max_retries(_), do: 0

  defp get_backoff_ms(%{"backoff_ms" => n}) when is_integer(n), do: n
  defp get_backoff_ms(%{backoff_ms: n}) when is_integer(n), do: n
  defp get_backoff_ms(_), do: 1000
end
