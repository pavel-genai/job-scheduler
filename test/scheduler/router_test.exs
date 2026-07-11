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
      ids = Enum.map(body["jobs"], & &1["id"])
      assert "j1" in ids
      assert "j2" in ids
      assert body["count"] == length(body["jobs"])
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

  describe "GET /health" do
    test "returns health check response" do
      conn = conn(:get, "/health") |> Router.call(@opts)

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") == ["application/json; charset=utf-8"]
      assert Jason.decode!(conn.resp_body) == %{"status" => "ok", "service" => "job-scheduler"}
    end
  end

  describe "POST /jobs with cron" do
    test "creates a job with valid cron expression" do
      conn =
        conn(:post, "/jobs", %{"name" => "cron_job", "cron" => "* * * * *"})
        |> put_req_header("content-type", "application/json")
        |> Router.call(@opts)

      assert conn.status == 201
    end

    test "rejects job with invalid cron expression" do
      conn =
        conn(:post, "/jobs", %{"name" => "bad_cron", "cron" => "not-a-cron"})
        |> put_req_header("content-type", "application/json")
        |> Router.call(@opts)

      assert conn.status == 400
      body = Jason.decode!(conn.resp_body)
      assert body["error"] =~ "Invalid cron"
    end
  end

  describe "POST /jobs with cycle" do
    test "rejects job that would create a dependency cycle" do
      # Create job "a" depending on "b"
      Scheduler.Store.put(Scheduler.Job.new(%{id: "a", name: "a", deps: ["b"]}))
      # Now try to create "b" depending on "a" -> cycle
      conn =
        conn(:post, "/jobs", %{"id" => "b", "name" => "b", "deps" => ["a"]})
        |> put_req_header("content-type", "application/json")
        |> Router.call(@opts)

      assert conn.status == 400
      body = Jason.decode!(conn.resp_body)
      assert body["error"] =~ "cycle"
    end
  end

  describe "unknown routes" do
    test "returns 404" do
      conn = conn(:get, "/unknown") |> Router.call(@opts)
      assert conn.status == 404
    end
  end
end
