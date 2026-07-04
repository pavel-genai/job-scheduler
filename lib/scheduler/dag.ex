defmodule Scheduler.DAG do
  @moduledoc """
  Manages Directed Acyclic Graph (DAG) dependencies between jobs.

  Provides cycle detection, topological sorting, and dependency
  resolution to determine which jobs are ready to run.
  """

  @doc """
  Validates that adding a job with the given dependencies does not create a cycle.
  Returns :ok or {:error, reason}.
  """
  @spec validate_no_cycle(String.t(), [String.t()], map()) :: :ok | {:error, String.t()}
  def validate_no_cycle(job_id, deps, existing_jobs) do
    graph = build_graph(existing_jobs)
    graph = Map.put(graph, job_id, deps)

    if has_cycle?(graph) do
      {:error, "Adding job #{job_id} with deps #{inspect(deps)} would create a cycle"}
    else
      :ok
    end
  end

  @doc """
  Returns a topological ordering of job IDs, or {:error, :cycle} if a cycle exists.
  """
  @spec topological_sort(map()) :: {:ok, [String.t()]} | {:error, :cycle}
  def topological_sort(jobs) do
    graph = build_graph(jobs)
    do_topological_sort(graph)
  end

  @doc """
  Returns the list of job IDs whose dependencies have all completed.
  """
  @spec ready_jobs([Scheduler.Job.t()]) :: [String.t()]
  def ready_jobs(jobs) do
    completed_ids =
      jobs
      |> Enum.filter(&(&1.status == :completed))
      |> Enum.map(& &1.id)
      |> MapSet.new()

    jobs
    |> Enum.filter(fn job ->
      job.status == :pending and deps_satisfied?(job.deps, completed_ids)
    end)
    |> Enum.map(& &1.id)
  end

  @doc """
  Checks if all dependencies for a job are satisfied (completed).
  """
  @spec deps_satisfied?([String.t()], MapSet.t()) :: boolean()
  def deps_satisfied?([], _completed_ids), do: true

  def deps_satisfied?(deps, completed_ids) do
    Enum.all?(deps, &MapSet.member?(completed_ids, &1))
  end

  @doc """
  Builds an adjacency list from a map/list of jobs.
  Each key is a job_id, value is list of dependency job_ids.
  """
  @spec build_graph(map() | [Scheduler.Job.t()]) :: map()
  def build_graph(jobs) when is_list(jobs) do
    Enum.reduce(jobs, %{}, fn job, acc ->
      Map.put(acc, job.id, job.deps || [])
    end)
  end

  def build_graph(jobs) when is_map(jobs) do
    Enum.reduce(jobs, %{}, fn
      {id, %{deps: deps}}, acc -> Map.put(acc, id, deps || [])
      {id, deps}, acc when is_list(deps) -> Map.put(acc, id, deps)
      {id, _}, acc -> Map.put(acc, id, [])
    end)
  end

  defp has_cycle?(graph) do
    nodes = Map.keys(graph)
    visited = MapSet.new()
    rec_stack = MapSet.new()

    Enum.any?(nodes, fn node ->
      if not MapSet.member?(visited, node) do
        {_visited, _stack, cyclic} = dfs_cycle(node, graph, visited, rec_stack)
        cyclic
      else
        false
      end
    end)
  end

  defp dfs_cycle(node, graph, visited, rec_stack) do
    visited = MapSet.put(visited, node)
    rec_stack = MapSet.put(rec_stack, node)

    neighbors = Map.get(graph, node, [])

    result =
      Enum.reduce_while(neighbors, {visited, rec_stack, false}, fn neighbor, {v, rs, _} ->
        cond do
          not MapSet.member?(v, neighbor) ->
            {v2, rs2, cyclic} = dfs_cycle(neighbor, graph, v, rs)

            if cyclic do
              {:halt, {v2, rs2, true}}
            else
              {:cont, {v2, rs2, false}}
            end

          MapSet.member?(rs, neighbor) ->
            {:halt, {v, rs, true}}

          true ->
            {:cont, {v, rs, false}}
        end
      end)

    {v, _rs, cyclic} = result
    {v, MapSet.delete(rec_stack, node), cyclic}
  end

  defp do_topological_sort(graph) do
    # Kahn's algorithm
    in_degree =
      Enum.reduce(graph, %{}, fn {node, _deps}, acc ->
        Map.put_new(acc, node, 0)
      end)

    in_degree =
      Enum.reduce(graph, in_degree, fn {_node, deps}, acc ->
        Enum.reduce(deps, acc, fn dep, a ->
          Map.update(a, dep, 1, &(&1 + 1))
        end)
      end)

    # Note: in this graph, edges go from dependency -> dependent,
    # but our graph stores deps (incoming edges), so we need to reverse.
    # Actually, we store {node => [deps]}, meaning node depends on deps.
    # For topological sort, we want deps to come before dependents.
    # in_degree should count how many nodes depend on each node... let's redo.

    # Recompute: in_degree[node] = number of deps node has
    all_nodes = Map.keys(graph) |> MapSet.new()

    dep_nodes =
      graph |> Map.values() |> List.flatten() |> MapSet.new()

    all_nodes = MapSet.union(all_nodes, dep_nodes)

    in_degree =
      Enum.reduce(all_nodes, %{}, fn node, acc ->
        deps = Map.get(graph, node, [])
        Map.put(acc, node, length(deps))
      end)

    queue =
      in_degree
      |> Enum.filter(fn {_node, deg} -> deg == 0 end)
      |> Enum.map(fn {node, _} -> node end)

    # Build reverse adjacency: for each dep, which nodes depend on it
    reverse =
      Enum.reduce(graph, %{}, fn {node, deps}, acc ->
        Enum.reduce(deps, acc, fn dep, a ->
          Map.update(a, dep, [node], &[node | &1])
        end)
      end)

    do_kahn(queue, reverse, in_degree, [])
  end

  defp do_kahn([], _reverse, in_degree, result) do
    if Enum.all?(in_degree, fn {_, deg} -> deg == 0 end) do
      {:ok, Enum.reverse(result)}
    else
      {:error, :cycle}
    end
  end

  defp do_kahn([node | rest], reverse, in_degree, result) do
    dependents = Map.get(reverse, node, [])

    {new_queue_additions, new_in_degree} =
      Enum.reduce(dependents, {[], in_degree}, fn dep, {q, deg} ->
        new_deg = Map.update!(deg, dep, &(&1 - 1))

        if new_deg[dep] == 0 do
          {[dep | q], new_deg}
        else
          {q, new_deg}
        end
      end)

    new_in_degree = Map.put(new_in_degree, node, 0)
    do_kahn(rest ++ new_queue_additions, reverse, new_in_degree, [node | result])
  end
end
