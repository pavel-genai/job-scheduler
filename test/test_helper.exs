ExUnit.start()

defmodule Scheduler.TestHelper do
  @moduledoc false
  def ok, do: :ok
  def always_fail, do: raise("intentional failure")
  def exit_fail, do: exit(:boom)
end
