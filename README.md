# JobScheduler

[![CI](https://github.com/pavel-genai/job-scheduler/actions/workflows/ci.yml/badge.svg)](https://github.com/pavel-genai/job-scheduler/actions/workflows/ci.yml)

An Elixir/OTP distributed job scheduler with DAG dependencies, configurable retry policies, and cron-based triggers.

## Features

- **DAG Dependencies**: Jobs run only after their dependencies complete successfully.
- **Retry Policies**: Configurable max retries and exponential backoff.
- **Cron Triggers**: Schedule jobs using cron expressions (parsed via Crontab).
- **Supervised Execution**: Jobs run as supervised Task processes.
- **State Tracking**: Jobs transition through pending, running, completed, failed, and retrying states.
- **HTTP Dashboard**: Plug-based REST API for managing and monitoring jobs.
- **ETS Storage**: Fast in-memory state storage.

## Architecture

```
lib/scheduler/
  job.ex      - Job struct and state definitions
  dag.ex      - DAG dependency resolution and validation
  runner.ex   - Supervised job execution with retry logic
  cron.ex     - Cron expression parsing and scheduling
  store.ex    - ETS-backed state storage
  router.ex   - Plug-based HTTP API
```

## API Endpoints

| Method | Path          | Description              |
|--------|---------------|--------------------------|
| POST   | /jobs         | Create a new job         |
| GET    | /jobs         | List all jobs            |
| GET    | /jobs/:id     | Get a specific job       |
| DELETE | /jobs/:id     | Delete a job             |
| GET    | /status       | System status overview   |

## Getting Started

```bash
mix deps.get
mix compile
mix run --no-halt
```

## Running Tests

```bash
mix test
```

## Job Definition Example

```json
{
  "name": "etl_transform",
  "module": "MyApp.ETL",
  "function": "transform",
  "args": ["input.csv"],
  "deps": ["etl_extract"],
  "retry_policy": {
    "max_retries": 3,
    "backoff_ms": 1000
  },
  "cron": "0 */6 * * *"
}
```
