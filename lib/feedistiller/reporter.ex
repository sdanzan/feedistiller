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

defmodule Feedistiller.Reporter do
  @moduledoc """
  Reporting functions and event broadcast
  """

  use GenStage
  require Logger
  import Feedistiller.Util
  alias Alambic.CountDown

  @doc "The stream of download events"
  @spec stream() :: GenStage.Stream.t
  def stream, do: GenStage.stream([{Feedistiller.Reporter, max_demand: 1}])

  @doc "Notify an event for the reporter to broadcast"
  @spec notify(Feedistiller.Event.t) :: :ok
  def notify(event) do
    GenStage.cast(__MODULE__, {:notify, event})
  end

  def start_link(_) do
    {:ok, pgs} = GenStage.start_link(__MODULE__, :ok, name: __MODULE__)
    %CountDown{id: pcd} = CountDown.create_link(2)
    Process.register(pcd, :flushed_check)
    {:ok, pgs}
  end

  def initial_state() do
    %{errors: 0, download: 0, total_bytes: 0, download_successful: 0, deleted: 0}
  end

  def reset() do
    CountDown.reset(%CountDown{id: :flushed_check}, 2)
    Agent.update(Feedistiller.Reporter.Reported, fn _ -> initial_state() end)
  end

  def wait_flushed() do
    CountDown.wait(%CountDown{id: :flushed_check})
  end

  def signal_flushed() do
    CountDown.signal(%CountDown{id: :flushed_check})
  end

  @impl true
  def init(:ok) do
    {:producer, :ok, dispatcher: GenStage.BroadcastDispatcher}
  end

  @impl true
  def handle_cast({:notify, event}, state) do
    {:noreply, [event], state}
  end

  @impl true
  def handle_demand(_demand, state) do
    {:noreply, [], state}
  end

  defmodule Reported do
    @moduledoc "Agent storing state for what has happened"
    use Agent

    def start_link(_arg) do
      Agent.start_link(&Feedistiller.Reporter.initial_state/0, name: __MODULE__)
    end
  end

  defmodule StreamToReported do
    @moduledoc "A process forwarding events to the `Feedistiller.Reporter.Reported` Agent."

    def child_spec(_arg) do
      %{
        id: StreamToReported,
        start: {StreamToReported, :start_link, []}
      }
    end

    def start_link do
      pid = spawn_link(fn ->
        for %Feedistiller.Event{entry: entry, event: event} <- Feedistiller.Reporter.stream do
          case event do
            {:complete, _} ->
              Feedistiller.Reporter.signal_flushed()
            {:begin, _filename} ->
              Agent.cast(Reported, fn state -> %{state | download: state.download + 1} end)
            {:finish_write, _filename, written, _time} ->
              Agent.cast(Reported, fn state ->
                state = %{state |
                  download_successful: state.download_successful + 1,
                  total_bytes: state.total_bytes + written
                }
                if written != entry.enclosure.size do
                  %{state | errors: state.errors + 1}
                else
                  state
                end
              end)
            {:error_write, _filename, _exception} ->
              Agent.cast(Reported, fn state ->
                %{state |
                  errors: state.errors + 1
                }
              end)
            {:clean, _} ->
              Agent.cast(Reported, fn state -> %{state | deleted: state.deleted + 1} end)
            bad when bad in [:error_destination, :bad_url, :bad_feed] ->
              Agent.cast(Reported, fn state -> %{state | errors: state.errors + 1} end)
            _ -> nil
          end
        end
      end)
      Process.register(pid, __MODULE__)
      {:ok, pid}
    end
  end

  @doc "Stream events to standard output."
  @spec sync_log_to_stdout() :: :ok
  def sync_log_to_stdout do
    for event <- stream(), do: log(event, &IO.puts/1, &IO.puts/1)
  end

  @doc "Starts a task streaming events to standard output."
  @spec log_to_stdout() :: Task.t
  def log_to_stdout do
    Task.async(&sync_log_to_stdout/0)
  end

  @doc "Stream events to Logger"
  @spec sync_log_to_logger() :: :ok
  def sync_log_to_logger do
    for event <- stream(), do: log(event, fn s -> Logger.info(s) end, fn s -> Logger.error(s) end)
  end

  @doc "Starts a task streaming events to Logger."
  @spec log_to_logger() :: Task.t
  def log_to_logger do
    Task.async(&sync_log_to_logger/0)
  end

  defp log(%Feedistiller.Event{feed: feed, destination: destination, entry: entry, event: event}, log_info, log_error) do
    case event do
      {:complete, _} -> Feedistiller.Reporter.signal_flushed()
      :begin_feed -> log_info.("Starting downloading feed #{feed.name}\n")
      {:end_feed, time} -> log_info.("Finished downloading feed #{feed.name} (#{tformat(time)})\n")
      {:end_enclosures, time} -> log_info.("Finished downloading enclosures for #{feed.name} (#{tformat(time)})\n")
      {:begin, filename} ->
        log_info.("[#{feed.name}] Starting download for `#{entry.title}`")
        log_info.("[#{feed.name}] Updated: #{dformat(entry.updated)}")
        log_info.("[#{feed.name}] Id: #{entry.id}")
        log_info.("[#{feed.name}] URL: #{entry.enclosure.url}")
        log_info.("[#{feed.name}] Destination: `#{destination}`")
        log_info.("[#{feed.name}] Saving to: `#{Path.basename(filename)}`")
        log_info.("[#{feed.name}] Expected size: #{entry.enclosure.size}\n")
      {:finish_write, _filename, written, time} ->
        log_info.("[#{feed.name}] Download finished for `#{entry.title}`")
        expected = entry.enclosure.size
        if expected == written do
          log_info.("[#{feed.name}] Total bytes: #{expected}")
        else
          log_error.("[#{feed.name}] Total bytes: #{written}, expected: #{expected}")
        end
        log_info.("[#{feed.name}] Total time: #{tformat(time)}\n")
      {:error_write, filename, exception} ->
        log_error.("[#{feed.name}] Error while writing to `#{Path.basename(filename)}` (complete path: `#{filename}`)")
        log_error.("[#{feed.name}] Exception: #{inspect exception}")
      {:error_destination, destination} -> log_error.("Destination unavailable: `#{destination}`")
      :bad_url -> log_error.("[#{feed.name}] Feed unavailable at #{feed.url}")
      :bad_feed -> log_error.("[#{feed.name}] Incomplete feed at #{feed.url}")
      :begin_clean -> log_info.("Starting cleaning for #{feed.name}")
      :end_clean -> log_info.("Ending cleaning for #{feed.name}")
      {:clean, file} -> log_info.("[#{feed.name}] Deleting file '#{file}'")
      {:bad_clean, file} -> log_info.("[#{feed.name}] Error deleting file '#{file}'")
      _ -> nil
    end
  end
end
