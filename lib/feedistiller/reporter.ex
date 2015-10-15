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
  Reporting functions.
  """
  
  @vsn 1

  require Logger
  
  defmodule Reported do
    @moduledoc "Name of the agent storing state"
  end
  
  defmodule StreamToReported do
    @moduledoc "A process forwarding events to the `Feedistiller.Reporter.Reported` Agent."
    
    def start_link do
      pid = spawn_link(fn ->
        GenEvent.stream(Feedistiller.Reporter)
        |> Enum.each(fn %Feedistiller.Event{destination: _dest, entry: entry, event: event} ->
          case event do
            {:begin, _filename} ->
              Agent.cast(Reported, fn state -> %{state | download: state.download + 1} end)
            {:write, _filename, _written} ->
              nil
            {:finish_write, _filename, written} ->
              Agent.cast(Reported, fn state -> 
                state = %{state | 
                  download_successful: state.download_successful + 1,
                  total_bytes: state.total_bytes + written
                }
                if written != entry.enclosure.size do
                  state = %{state | errors: state.errors + 1}
                end
                state
              end)
            {:error_write, _filename, written, _exception} ->
              Agent.cast(Reported, fn state -> 
                %{state | 
                  errors: state.errors + 1,
                  total_bytes: state.total_bytes + written
                }
              end)
            {:error_destination, _destination} ->
              Agent.cast(Reported, fn state -> %{state | errors: state.errors + 1} end)
            {:bad_url, _url} ->
              Agent.cast(Reported, fn state -> %{state | errors: state.errors + 1} end)
            {:bad_feed, _url} ->
              Agent.cast(Reported, fn state -> %{state | errors: state.errors + 1} end)
          end
        end)
      end)
      Process.register(pid, __MODULE__)
      {:ok, pid}
    end
  end

  @doc "Stream events to standard output."
  @spec sync_log_to_stdout() :: :ok
  def sync_log_to_stdout do
    GenEvent.stream(Feedistiller.Reporter)
    |> Enum.each(fn event -> log(event, &IO.puts/1, &IO.puts/1) end)
  end

  @doc "Starts a task streaming events to standard output."
  @spec log_to_stdout() :: Task.t
  def log_to_stdout do
    Task.async(&sync_log_to_stdout/0)
  end

  @doc "Stream events to Logger"
  @spec sync_log_to_logger() :: :ok
  def sync_log_to_logger do
    GenEvent.stream(Feedistiller.Reporter)
    |> Enum.each(fn event -> log(event, fn s -> Logger.info(s) end, fn s -> Logger.error(s) end) end)
  end

  @doc "Starts a task streaming events to Logger."
  @spec log_to_logger() :: Task.t
  def log_to_logger do
    Task.async(&sync_log_to_logger/0)
  end

  defp log(%Feedistiller.Event{destination: destination, entry: entry, event: event}, log_info, log_error) do
    case event do
      {:begin, filename} ->
        log_info.("Starting download for `#{entry.title}`")
        log_info.("URL: #{entry.enclosure.url}")
        log_info.("Destination: `#{destination}`")
        log_info.("Saving to: `#{Path.basename(filename)}`")
        log_info.("Expected size: #{entry.enclosure.size}\n")
      {:write, _filename, _written} ->
        nil
      {:finish_write, _filename, written} ->
        log_info.("Download finished for `#{entry.title}`")
        expected = entry.enclosure.size
        if expected == written do
          log_info.("Total bytes: #{expected}\n")
        else
          log_error.("Total bytes: #{written}, expected: #{expected}\n")
        end
      {:error_write, filename, _written, exception} ->
        log_error.("Error while writing to `#{Path.basename(filename)}` (complete path: `#{filename}`)")
        log_error.("Exception: #{inspect exception}")
      {:error_destination, destination} ->
        log_error.("Destination unavailable: `#{destination}`")
      {:bad_url, url} ->
        log_error.("Feed unavailable at #{url}")
      {:bad_feed, url} ->
        log_error.("Incomplete feed at #{url}")
    end
  end
end
