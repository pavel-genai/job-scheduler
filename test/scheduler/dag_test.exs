defmodule Scheduler.DAGTest do
  use ExUnit.Case, async: true

  alias Scheduler.DAG
  alias Scheduler.Job

  describe "validate_no_cycle/3" do
    test "allows valid dependencies" do
      existing = %{"a" => [], "b" => ["a"]}
      assert :ok = DAG.validate_no_cycle("c", ["b"], existing)
    end

    test "detects direct cycle" do
      existing = %{"a" => ["b"]}
      assert {:error, _} = DAG.validate_no_cycle("b", ["a"], existing)
    end

    test "allows job with no deps" do
      existing = %{"a" => []}
      assert :ok = DAG.validate_no_cycle("b", [], existing)
    end
  end

  describe "ready_jobs/1" do
    test "returns jobs with no deps that are pending" do
      jobs = [
        %Job{Job.new(%{id: "a", name: "a"}) | status: :pending, deps: []},
        %Job{Job.new(%{id: "b", name: "b"}) | status: :pending, deps: ["a"]}
      ]

      ready = DAG.ready_jobs(jobs)
      assert ready == ["a"]
    end

    test "returns jobs whose deps are all completed" do
      jobs = [
        %Job{Job.new(%{id: "a", name: "a"}) | status: :completed, deps: []},
        %Job{Job.new(%{id: "b", name: "b"}) | status: :pending, deps: ["a"]}
      ]

      ready = DAG.ready_jobs(jobs)
      assert ready == ["b"]
    end

    test "returns empty list when no jobs are ready" do
      jobs = [
        %Job{Job.new(%{id: "a", name: "a"}) | status: :running, deps: []},
        %Job{Job.new(%{id: "b", name: "b"}) | status: :pending, deps: ["a"]}
      ]

      ready = DAG.ready_jobs(jobs)
      assert ready == []
    end
  end

  describe "topological_sort/1" do
    test "sorts a simple DAG" do
      jobs = %{"a" => [], "b" => ["a"], "c" => ["b"]}
      assert {:ok, order} = DAG.topological_sort(jobs)
      assert Enum.find_index(order, &(&1 == "a")) < Enum.find_index(order, &(&1 == "b"))
      assert Enum.find_index(order, &(&1 == "b")) < Enum.find_index(order, &(&1 == "c"))
    end

    test "detects cycle" do
      jobs = %{"a" => ["b"], "b" => ["a"]}
      assert {:error, :cycle} = DAG.topological_sort(jobs)
    end
  end

  describe "deps_satisfied?/2" do
    test "returns true when all deps are completed" do
      completed = MapSet.new(["a", "b"])
      assert DAG.deps_satisfied?(["a", "b"], completed)
    end

    test "returns false when some deps are not completed" do
      completed = MapSet.new(["a"])
      refute DAG.deps_satisfied?(["a", "b"], completed)
    end

    test "returns true for empty deps" do
      assert DAG.deps_satisfied?([], MapSet.new())
    end
  end
end
