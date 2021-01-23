# Copyright 2015 Serge Danzanvilliers <serge.danzanvilliers@gmail.com>
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

defmodule Feedistiller.Supervisor do
  @moduledoc "Supervisor for Feedistiller. Essentially ensures the event reporter is started."
 
  use Supervisor
  use Application
 
  @impl true
  def start(_, _) do
    start_link()
  end
 
  @doc "Let's start!"
  def start_link do
    Supervisor.start_link(__MODULE__, :ok, [])
  end
 
 
  @impl true
  def init(:ok) do
    children = [
      Feedistiller.Reporter,
      Feedistiller.Reporter.Reported,
      Feedistiller.Reporter.StreamToReported
    ]
    
    Supervisor.init(children, strategy: :one_for_one)
  end
end
