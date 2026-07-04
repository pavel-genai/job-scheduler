defmodule Scheduler.StoreTest do
  use ExUnit.Case

  alias Scheduler.{Job, Store}

  setup do
    # The store is started by the application; clear it between tests
    Store.clear()
    :ok
  end

  describe "put/1 and get/1" do
    test "stores and retrieves a job" do
      job = Job.new(%{id: "test-1", name: "test"})
      assert :ok = Store.put(job)
      assert {:ok, retrieved} = Store.get("test-1")
      assert retrieved.name == "test"
    end

    test "returns error for non-existent job" do
      assert {:error, :not_found} = Store.get("nonexistent")
    end
  end

  describe "all/0" do
    test "returns all stored jobs" do
      Store.put(Job.new(%{id: "a", name: "a"}))
      Store.put(Job.new(%{id: "b", name: "b"}))

      jobs = Store.all()
      ids = Enum.map(jobs, & &1.id) |> Enum.sort()
      assert ids == ["a", "b"]
    end

    test "returns empty list when no jobs" do
      assert Store.all() == []
    end
  end

  describe "delete/1" do
    test "deletes an existing job" do
      job = Job.new(%{id: "del-1", name: "delete_me"})
      Store.put(job)
      assert :ok = Store.delete("del-1")
      assert {:error, :not_found} = Store.get("del-1")
    end

    test "returns error for non-existent job" do
      assert {:error, :not_found} = Store.delete("nonexistent")
    end
  end

  describe "by_status/1" do
    test "filters jobs by status" do
      Store.put(%{Job.new(%{id: "p1", name: "p1"}) | status: :pending})
      Store.put(%{Job.new(%{id: "r1", name: "r1"}) | status: :running})
      Store.put(%{Job.new(%{id: "c1", name: "c1"}) | status: :completed})

      pending = Store.by_status(:pending)
      assert length(pending) == 1
      assert hd(pending).id == "p1"
    end
  end

  describe "status_counts/0" do
    test "returns counts grouped by status" do
      Store.put(%{Job.new(%{id: "p1", name: "p1"}) | status: :pending})
      Store.put(%{Job.new(%{id: "p2", name: "p2"}) | status: :pending})
      Store.put(%{Job.new(%{id: "r1", name: "r1"}) | status: :running})

      counts = Store.status_counts()
      assert counts[:pending] == 2
      assert counts[:running] == 1
    end
  end

  describe "update/2" do
    test "updates a job with a function" do
      Store.put(Job.new(%{id: "u1", name: "original"}))

      assert {:ok, updated} = Store.update("u1", fn job ->
        %{job | name: "updated"}
      end)

      assert updated.name == "updated"
    end

    test "returns error for non-existent job" do
      assert {:error, :not_found} = Store.update("nonexistent", fn j -> j end)
    end
  end

  describe "clear/0" do
    test "removes all jobs" do
      Store.put(Job.new(%{id: "a", name: "a"}))
      Store.put(Job.new(%{id: "b", name: "b"}))
      Store.clear()
      assert Store.all() == []
    end
  end
end
