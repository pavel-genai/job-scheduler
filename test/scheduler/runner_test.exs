defmodule Scheduler.RunnerTest do
  use ExUnit.Case, async: false

  alias Scheduler.{Job, Runner, Store}

  defp wait_for(fun, timeout \\ 1000) do
    deadline = System.monotonic_time(:millisecond) + timeout

    wait_loop(fun, deadline)
  end

  defp wait_loop(fun, deadline) do
    if fun.() do
      :ok
    else
      if System.monotonic_time(:millisecond) < deadline do
        Process.sleep(20)
        wait_loop(fun, deadline)
      else
        flunk("wait_for timed out")
      end
    end
  end

  setup do
    Store.clear()
    :ok
  end

  describe "submit/1" do
    test "submits a pending job and runs it to completion" do
      job = Job.new(%{id: "runner-1", name: "ok_job", module: "Scheduler.TestHelper", function: "ok", args: []})
      Store.put(job)

      assert :ok = Runner.submit("runner-1")

      # Give the async task time to complete.
      wait_for(fn -> match?({:ok, %{status: :completed}}, Store.get("runner-1")) end)

      assert {:ok, completed} = Store.get("runner-1")
      assert completed.status == :completed
      assert completed.attempts == 1
    end

    test "returns error for non-existent job" do
      assert {:error, :not_found} = Runner.submit("does-not-exist")
    end

    test "returns error for job in invalid status" do
      job = %Job{Job.new(%{id: "runner-2", name: "done"}) | status: :completed}
      Store.put(job)

      assert {:error, {:invalid_status, :completed}} = Runner.submit("runner-2")
    end
  end

  describe "retry logic" do
    test "retries a failing job up to max_retries then marks failed" do
      job = Job.new(%{
        id: "runner-retry",
        name: "flaky",
        module: "Scheduler.TestHelper",
        function: "exit_fail",
        args: [],
        retry_policy: %{"max_retries" => 2, "backoff_ms" => 10}
      })
      Store.put(job)

      assert :ok = Runner.submit("runner-retry")

      # Wait for all retries to exhaust.
      wait_for(fn -> match?({:ok, %{status: :failed}}, Store.get("runner-retry")) end, 2000)

      assert {:ok, failed} = Store.get("runner-retry")
      assert failed.status == :failed
    end
  end

  describe "maybe_run_ready_jobs/0" do
    test "starts jobs whose dependencies are completed" do
      dep = %Job{Job.new(%{id: "dep-1", name: "dep"}) | status: :completed}
      Store.put(dep)

      child = Job.new(%{id: "child-1", name: "child", deps: ["dep-1"], module: "Scheduler.TestHelper", function: "ok"})
      Store.put(child)

      Runner.maybe_run_ready_jobs()

      wait_for(fn -> match?({:ok, %{status: :completed}}, Store.get("child-1")) end)

      assert {:ok, completed} = Store.get("child-1")
      assert completed.status == :completed
    end
  end
end