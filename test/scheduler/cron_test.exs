defmodule Scheduler.CronTest do
  use ExUnit.Case, async: true

  alias Scheduler.Cron

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
end
