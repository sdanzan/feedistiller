defmodule Feedistiller.Supervisor do
  @moduledoc "Supervisor for Feedistiller. Essentially ensures the event reporter is started."
  @vsn 1
  
  use Supervisor
  use Application
  
  @doc "Let's start!"
  def start(_, _) do
    start_link
  end
  
  @doc "Let's start!"
  def start_link do
    Supervisor.start_link(__MODULE__, :ok)
  end
  
  @reporter_name Feedistiller.Reporter
  @reported_name Feedistiller.Reporter.Reported
  
  def init(:ok) do
    children = [
      worker(GenEvent, [[name: @reporter_name]]),
      worker(Agent, [fn -> %{errors: 0, download: 0, total_bytes: 0, download_successful: 0} end, [name: @reported_name]]),
      worker(Feedistiller.Reporter.StreamToReported, [])
    ]
    
    supervise(children, strategy: :one_for_one)
  end
end
