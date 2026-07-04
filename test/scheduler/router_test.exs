defmodule Scheduler.RouterTest do
  use ExUnit.Case
  use Plug.Test

  alias Scheduler.Router

  @opts Router.init([])

  setup do
    Scheduler.Store.clear()
    :ok
  end

  describe "POST /jobs" do
    test "creates a new job" do
      conn =
        conn(:post, "/jobs", %{"name" => "test_job"})
        |> put_req_header("content-type", "application/json")
        |> Router.call(@opts)

      assert conn.status == 201
      body = Jason.decode!(conn.resp_body)
      assert body["ok"] == true
      assert body["job"]["name"] == "test_job"
      assert body["job"]["status"] == "pending"
    end
  end

  describe "GET /jobs" do
    test "returns empty list when no jobs" do
      conn = conn(:get, "/jobs") |> Router.call(@opts)

      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert body["jobs"] == []
      assert body["count"] == 0
    end

    test "returns all jobs" do
      Scheduler.Store.put(Scheduler.Job.new(%{id: "j1", name: "job1"}))
      Scheduler.Store.put(Scheduler.Job.new(%{id: "j2", name: "job2"}))

      conn = conn(:get, "/jobs") |> Router.call(@opts)

      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert body["count"] == 2
    end
  end

  describe "GET /jobs/:id" do
    test "returns a job by id" do
      Scheduler.Store.put(Scheduler.Job.new(%{id: "j1", name: "job1"}))

      conn = conn(:get, "/jobs/j1") |> Router.call(@opts)

      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert body["job"]["id"] == "j1"
    end

    test "returns 404 for non-existent job" do
      conn = conn(:get, "/jobs/nonexistent") |> Router.call(@opts)

      assert conn.status == 404
    end
  end

  describe "DELETE /jobs/:id" do
    test "deletes an existing job" do
      Scheduler.Store.put(Scheduler.Job.new(%{id: "j1", name: "job1"}))

      conn = conn(:delete, "/jobs/j1") |> Router.call(@opts)

      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert body["ok"] == true
    end

    test "returns 404 for non-existent job" do
      conn = conn(:delete, "/jobs/nonexistent") |> Router.call(@opts)

      assert conn.status == 404
    end
  end

  describe "GET /status" do
    test "returns system status" do
      conn = conn(:get, "/status") |> Router.call(@opts)

      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert body["status"] == "running"
      assert is_integer(body["total_jobs"])
    end
  end

  describe "unknown routes" do
    test "returns 404" do
      conn = conn(:get, "/unknown") |> Router.call(@opts)
      assert conn.status == 404
    end
  end
end
