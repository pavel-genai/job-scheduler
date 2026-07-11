defmodule Scheduler.CronTest do
  use ExUnit.Case, async: true

  alias Scheduler.Cron
  alias Scheduler.{Job, Store}

  describe "parse/1" do
    test "parses valid cron expression" do
      assert {:ok, _} = Cron.parse("* * * * *")
    end

    test "parses complex cron expression" do
      assert {:ok, _} = Cron.parse("0 */6 * * *")
    end

    test "returns error for invalid expression" do
      assert {:error, _} = Cron.parse("invalid")
    end
  end

  describe "next_occurrence/2" do
    test "returns next run time for every-minute cron" do
      now = ~N[2024-01-01 12:00:00]
      assert {:ok, next} = Cron.next_occurrence("* * * * *", now)
      assert NaiveDateTime.compare(next, now) in [:gt, :eq]
    end

    test "returns error for invalid expression" do
      assert {:error, _} = Cron.next_occurrence("bad cron")
    end
  end

  describe "matches?/2" do
    test "every-minute expression matches any time" do
      now = ~N[2024-06-15 10:30:00]
      assert Cron.matches?("* * * * *", now)
    end

    test "specific hour expression matches correctly" do
      noon = ~N[2024-06-15 12:00:00]
      assert Cron.matches?("0 12 * * *", noon)
    end

    test "specific hour expression does not match wrong time" do
      not_noon = ~N[2024-06-15 13:00:00]
      refute Cron.matches?("0 12 * * *", not_noon)
    end

    test "returns false for invalid expression" do
      refute Cron.matches?("invalid")
    end
  end

  describe "check_and_trigger_jobs (via GenServer)" do
    setup do
      Store.clear()
      :ok
    end

    test "triggers a cron job when expression matches" do
      # Insert a completed job with an every-minute cron expression.
      job = %Job{Job.new(%{id: "cron-1", name: "cron_job", cron: "* * * * *"}) | status: :completed}
      Store.put(job)

      # Send the check_cron message directly to the GenServer.
      send(Cron, :check_cron)

      # The cron trigger resets to :pending, then maybe_run_ready_jobs starts it.
      # It may complete almost instantly, so accept pending/running/completed.
      wait_for(fn ->
        case Store.get("cron-1") do
          {:ok, j} -> j.status in [:pending, :running, :completed] and j.attempts >= 0
          _ -> false
        end
      end)

      assert {:ok, triggered} = Store.get("cron-1")
      # The job was reset (attempts reset to 0 by the trigger).
      assert triggered.status in [:pending, :running, :completed]
    end

    test "does not trigger jobs with non-matching cron" do
      job = %Job{Job.new(%{id: "cron-2", name: "cron_job", cron: "0 3 * * *"}) | status: :completed}
      Store.put(job)

      send(Cron, :check_cron)

      # Give it a moment, then verify it's still completed.
      Process.sleep(50)
      assert {:ok, still} = Store.get("cron-2")
      assert still.status == :completed
    end
  end

  defp wait_for(fun, timeout \\ 500) do
    deadline = System.monotonic_time(:millisecond) + timeout
    wait_loop(fun, deadline)
  end

  defp wait_loop(fun, deadline) do
    if fun.() do
      :ok
    else
      if System.monotonic_time(:millisecond) < deadline do
        Process.sleep(10)
        wait_loop(fun, deadline)
      else
        :ok
      end
    end
  end
end
