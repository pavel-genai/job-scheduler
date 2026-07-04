defmodule Scheduler.JobTest do
  use ExUnit.Case, async: true

  alias Scheduler.Job

  describe "new/1" do
    test "creates a job with default values" do
      job = Job.new(%{"name" => "test_job"})

      assert job.name == "test_job"
      assert job.status == :pending
      assert job.attempts == 0
      assert job.deps == []
      assert job.args == []
      assert job.id != nil
    end

    test "creates a job with atom keys" do
      job = Job.new(%{name: "test_job", deps: ["dep1"], args: ["arg1"]})

      assert job.name == "test_job"
      assert job.deps == ["dep1"]
      assert job.args == ["arg1"]
    end

    test "sets retry policy from attributes" do
      job = Job.new(%{
        "name" => "retry_job",
        "retry_policy" => %{"max_retries" => 3, "backoff_ms" => 2000}
      })

      assert job.max_retries == 3
      assert job.backoff_ms == 2000
    end

    test "defaults to 0 retries and 1000ms backoff" do
      job = Job.new(%{"name" => "no_retry"})

      assert job.max_retries == 0
      assert job.backoff_ms == 1000
    end
  end

  describe "transition/2" do
    test "allows pending -> running" do
      job = Job.new(%{"name" => "test"})
      assert {:ok, updated} = Job.transition(job, :running)
      assert updated.status == :running
      assert updated.started_at != nil
    end

    test "allows running -> completed" do
      job = %{Job.new(%{"name" => "test"}) | status: :running}
      assert {:ok, updated} = Job.transition(job, :completed)
      assert updated.status == :completed
      assert updated.completed_at != nil
    end

    test "allows running -> retrying" do
      job = %{Job.new(%{"name" => "test"}) | status: :running}
      assert {:ok, updated} = Job.transition(job, :retrying)
      assert updated.status == :retrying
    end

    test "allows running -> failed" do
      job = %{Job.new(%{"name" => "test"}) | status: :running}
      assert {:ok, updated} = Job.transition(job, :failed)
      assert updated.status == :failed
    end

    test "allows retrying -> running" do
      job = %{Job.new(%{"name" => "test"}) | status: :retrying}
      assert {:ok, updated} = Job.transition(job, :running)
      assert updated.status == :running
    end

    test "rejects invalid transitions" do
      job = Job.new(%{"name" => "test"})
      assert {:error, _} = Job.transition(job, :completed)
    end

    test "rejects invalid status" do
      job = Job.new(%{"name" => "test"})
      assert {:error, _} = Job.transition(job, :unknown)
    end
  end
end
