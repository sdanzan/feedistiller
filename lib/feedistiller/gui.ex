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

defmodule Feedistiller.GUI do
  @moduledoc """
  Graphic user interface for Feedistiller. This is implemented
  as a GenServer listening to Feedistiller.Reporter events and
  updating the gui accordingly.
  """

  use GenServer
  import Feedistiller.Util
  alias Feedistiller.Event
  alias Feedistiller.Feeder
  alias Feedistiller.GUI

  @defaultcolor {236, 236, 236}
  @red {255, 0, 0}
  @blue {73, 167, 244}
  @green {0, 255, 0}
  @yellow {255, 255, 0}
  @start_width 600
  @start_height 371

  defstruct wx: nil, frame: nil,
            data: %{current: 0, total: 0, total_bytes: 0, finished: 0, complete: false, time: nil},
            feeds: %{page: nil, sizer: nil, f: Map.new()},
            items: %{page1: nil, page2: nil, sizer1: nil, sizer2: nil, i: Map.new()}

  defp hrbytes(bytes) do
    case div(bytes, 1024*1024) do
      0 -> "#{div(bytes, 1024)}K"
      n -> case div(n, 1024) do
        0 -> "#{n}M"
        m -> "#{m}.#{n - m * 1024}G"
      end
    end
  end

  defp percent(_, e) when not is_integer(e), do: "?"
  defp percent(current, expected), do: div(current * 100, expected)

  defp listen(pid, stream) do
    for event <- stream, do: GenServer.cast(pid, event)
  end

  defp set_status_text(f, data) do
    if data.complete do
      :wxFrame.setStatusText(f, String.to_charlist(
        "Downloaded: #{data.total} - Downloading: finished - Bytes: #{data.total_bytes} (#{hrbytes(data.total_bytes)}) - Finished: #{data.finished} - Time: #{tformat(data.time)}"))
    else
      :wxFrame.setStatusText(f, String.to_charlist(
        "Downloaded: #{data.total} - Downloading: #{data.current} - Bytes: #{data.total_bytes} (#{hrbytes(data.total_bytes)}) - Finished: #{data.finished}"))
    end
  end

  defp set_header_text(feed, info) do
    s = "#{feed.name}"
    s = if info.channel, do: s <> " (\"#{info.channel.title}\")", else: s
    s = s <> "\nDestination: #{Path.join(feed.destination, feed.name)}\nDownloaded: #{info.total}"
    s = if info.complete do
      :wxStaticText.setBackgroundColour(info.header, @green)
      s <> "\nDownloading: finished (time: #{tformat(info.time)})"
    else
      if info.current > 0 do
        :wxStaticText.setBackgroundColour(info.header, @blue)
      else
        :wxStaticText.setBackgroundColour(info.header, @defaultcolor)
      end
      s <> "\nDownloading: #{info.current}"
    end
    s = s <> "\nBytes: #{info.bytes}"
    s = if info.bytes >= 1024, do: s <> " (#{hrbytes(info.bytes)})#{}", else: s
    :wxStaticText.setLabel(info.header, String.to_charlist(s))
  end

  defp panel(t, n) do
    p = :wxScrolledWindow.new(t)
    :wxScrolledWindow.setScrollRate(p, 5, 5)
    s = :wxBoxSizer.new(:wx_const.wx_vertical)
    :wxScrolledWindow.setSizer(p, s)
    true = :wxNotebook.addPage(t, p, n)
    {p, s}
  end

  def init({parent, stream}) do
    w = :wx.new()
    f = :wxFrame.new(w, -1, 'Feedistiller - running', [size: {@start_width, @start_height}])
    pid = self()
    :wxFrame.connect(f, :close_window, [callback: fn (_, _) -> GenServer.cast(pid, {:close, parent}) end]) 
    :wxFrame.createStatusBar(f)
    set_status_text(f, %{current: 0, total: 0, total_bytes: 0, finished: 0, complete: false, time: nil})
    t = :wxNotebook.new(f, -1)

    {p1, s1} = panel(t, 'Feeds')
    {p2, s2} = panel(t, 'Active downloads')
    {p3, s3} = panel(t, 'Completed downloads')

    :wxFrame.show(f)

    spawn_link(fn -> listen(pid, stream) end)
    {:ok, %GUI{wx: w, frame: f,
        feeds: %{page: p1, sizer: s1, f: Map.new()},
        items: %{page1: p2, sizer1: s2, page2: p3, sizer2: s3, i: Map.new()}
      }
    }
  end

  def handle_cast({:close, parent}, state) do
    :wxFrame.destroy(state.frame)
    :wx.destroy()
    send(parent, :close)
    {:stop, :normal, state}
  end

  # A feed is starting
  def handle_cast(event = %Event{event: :begin_feed}, state = %GUI{}) do
    flags = :wxSizerFlags.new |> :wxSizerFlags.expand |> :wxSizerFlags.border
    if Enum.count(state.feeds.f) > 0 do
      :wxBoxSizer.add(state.feeds.sizer, :wxStaticLine.new(state.feeds.page), flags)
    end

    header = :wxStaticText.new(state.feeds.page, -1, '')
    :wxBoxSizer.add(state.feeds.sizer, header, flags)
    :wxSizerFlags.destroy(flags)

    info = %{
      header: header,
      current: 0,
      total: 0,
      bytes: 0,
      complete: false,
      time: nil,
      channel: nil
    }
    set_header_text(event.feed, info)

    # Refresh view
    :wxWindow.fitInside(state.feeds.page)

    {:noreply, %GUI{state |
        feeds: %{state.feeds |
          f: Map.put(state.feeds.f, event.feed.name, info)
        }
      }
    }
  end

  # Got a complete channel
  def handle_cast(event = %Event{event: {:channel_complete, channel}}, state = %GUI{}) do
    info = %{Map.fetch!(state.feeds.f, event.feed.name) | channel: channel}
    set_header_text(event.feed, info)
    :wxWindow.fitInside(state.feeds.page)
    {:noreply, %GUI{ state |
        feeds: %{ state.feeds |
          f: Map.put(state.feeds.f, event.feed.name, info)
        }
      }
    }
  end

  # A feed finished downloading enclosures
  def handle_cast(event = %Event{event: {:end_enclosures, time}}, state = %GUI{}) do
    state = %GUI{state | data: %{state.data | finished: state.data.finished + 1}}
    set_status_text(state.frame, state.data)
    info = %{Map.fetch!(state.feeds.f, event.feed.name) | complete: true, time: time}
    set_header_text(event.feed, info)
    :wxWindow.fitInside(state.feeds.page)
    {:noreply, %GUI{ state |
        feeds: %{ state.feeds |
          f: Map.put(state.feeds.f, event.feed.name, info)
        }
      }
    }
  end

  # Begin downloading an enclosure
  def handle_cast(event = %Event{event: {:begin, filename}}, state = %GUI{}) do
    # Update global feedback
    info = Map.fetch!(state.feeds.f, event.feed.name)
    info = %{info | current: info.current + 1}
    set_header_text(event.feed, info)

    # Add gauge for the new file
    inpanel = :wxPanel.new(state.items.page1)
    insizer = :wxBoxSizer.new(:wx_const.wx_vertical)
    :wxPanel.setSizer(inpanel, insizer)
    name = event.feed.name <> " - " <> dformat(event.entry.updated) <> ": " <> event.entry.title
    :wxBoxSizer.add(insizer, :wxStaticText.new(inpanel, -1, String.to_charlist(name)))
    gauge = :wxGauge.new(inpanel, -1, -1)
    case event.entry.enclosure.size do
      nil -> :wxGauge.pulse(gauge)
      s when s <= 0 -> :wxGauge.pulse(gauge)
      s -> :wxGauge.setRange(gauge, s)
    end
    flags = :wxSizerFlags.new |> :wxSizerFlags.expand
    :wxBoxSizer.add(insizer, gauge, flags)
    bytes = :wxStaticText.new(inpanel, -1, 'Bytes: 0')
    :wxBoxSizer.add(insizer, bytes)
    flags = flags |> :wxSizerFlags.border
    :wxBoxSizer.add(state.items.sizer1, inpanel, flags)
    :wxBoxSizer.add(state.items.sizer1, :wxStaticLine.new(state.items.page1), flags)
    :wxSizerFlags.destroy(flags)

    # Refresh view
    :wxWindow.fitInside(state.items.page1)
    h = :wxWindow.getScrollRange(state.items.page1, :wx_const.wx_vertical)
    :wxScrolledWindow.scroll(state.items.page1, 0, h)
    
    state = %GUI{state |
        data: %{state.data | current: state.data.current + 1},
        feeds: %{state.feeds | f: Map.put(state.feeds.f, event.feed.name, info)},
        items: %{state.items | i: Map.put(state.items.i, filename, {gauge, bytes, inpanel})}
      }
    set_status_text(state.frame, state.data)
    {:noreply, state}
  end

  # Write a chunk of enclosure data to the disk
  def handle_cast(event = %Event{event: {:write, filename, written}}, state = %GUI{}) do
    handle_write(event, filename, written, nil, state)
    {:noreply, state}
  end

  # Finished downloading an enclosure
  def handle_cast(event = %Event{event: {:finish_write, filename, written, time}}, state = %GUI{}) do
    event = if !event.entry.enclosure.size || event.entry.enclosure.size <= 0 do
      %Event{event | 
        entry: %Feeder.Entry{event.entry | 
          enclosure: %Feeder.Enclosure{event.entry.enclosure | size: written}
        }
      }
    else
      event
    end
    handle_write(event, filename, written, time, state)

    state = %GUI{state | 
      data: %{state.data | 
        current: state.data.current - 1, total: state.data.total + 1, total_bytes: state.data.total_bytes + written
      }
    }
    set_status_text(state.frame, state.data)
    info = Map.fetch!(state.feeds.f, event.feed.name)
    info = %{info | current: info.current - 1, total: info.total + 1, bytes: info.bytes + written}
    set_header_text(event.feed, info)
    {gauge, _, gaugepanel} = Map.fetch!(state.items.i, filename)
    :wxGauge.destroy(gauge)
    move_to_completed_panel(state.items, gaugepanel)
    :wxPanel.setBackgroundColour(gaugepanel, @green)
    :wxPanel.refresh(gaugepanel)
    {:noreply, %GUI{state |
        feeds: %{state.feeds |
          f: Map.put(state.feeds.f, event.feed.name, info)
        }
      }
    }
  end

  # Error while writing to an enclosure file
  def handle_cast(event = %Event{event: {:error_write, filename, _exception}}, state = %GUI{}) do
    state = %GUI{state | 
      data: %{state.data | 
        current: state.data.current - 1
      }
    }
    set_status_text(state.frame, state.data)
    info = Map.fetch!(state.feeds.f, event.feed.name)
    info = %{info | current: info.current - 1}
    set_header_text(event.feed, info)
    {gauge, _, gaugepanel} = Map.fetch!(state.items.i, filename)
    :wxGauge.destroy(gauge)
    move_to_completed_panel(state.items, gaugepanel)
    :wxPanel.setBackgroundColour(gaugepanel, @red)
    :wxPanel.refresh(gaugepanel)
    {:noreply, %GUI{state |
        feeds: %{state.feeds |
          f: Map.put(state.feeds.f, event.feed.name, info)
        }
      }
    }
  end

  # Error opening a destination directory
  def handle_cast(%Event{event: {:error_destination, _destination}}, state = %GUI{}) do
    {:noreply, state}
  end

  # No feed at the given address
  def handle_cast(event = %Event{event: :bad_url}, state = %GUI{}) do
    handle_bad_feed(event, state)
  end

  # Feed is malformed
  def handle_cast(event = %Event{event: :bad_feed}, state = %GUI{}) do
    handle_bad_feed(event, state)
  end

  # All complete
  def handle_cast(%Event{event: {:complete, timestamp}}, state = %GUI{}) do
    state = %GUI{state | data: %{state.data | complete: true, time: timestamp}}
    set_status_text(state.frame, state.data)
    :wxFrame.setTitle(state.frame, 'Feedistiller - all complete')
    {:noreply, state}
  end

  def handle_cast(_, state = %GUI{}) do
    {:noreply, state}
  end

  defp handle_write(event, filename, written, time, state) do
    {gauge, bytes, _} = Map.fetch!(state.items.i, filename)
    label = "Bytes: #{written} (#{hrbytes(written)})"
    label = if event.entry.enclosure.size && event.entry.enclosure.size > 0 do
      :wxGauge.setValue(gauge, written)
      label <> " - #{percent(written, event.entry.enclosure.size)}%"
    else
      label
    end
    label = if !is_nil(time), do: label <> " - Time: #{tformat(time)}", else: label
    :wxStaticText.setLabel(bytes, String.to_charlist(label))
  end

  defp handle_bad_feed(event, state) do
    info = %{Map.fetch!(state.feeds.f, event.feed.name) | complete: true}
    set_header_text(event.feed, info)
    :wxStaticText.setBackgroundColour(info.header, (if info.total > 0, do: @yellow, else: @red))
    :wxStaticText.refresh(info.header)
    {:noreply, %GUI{state |
        feeds: %{state.feeds |
          f: Map.put(state.feeds.f, event.feed.name, info)
        }
      }
    }
  end
  
  defp move_to_completed_panel(panels, gauge) do
    id = :wxWindow.getId(gauge)
    idx = Enum.find_index(:wxSizer.getChildren(panels.sizer1), fn si -> id == :wxWindow.getId(:wxSizerItem.getWindow(si)) end)
    :wxSizer.remove(panels.sizer1, idx + 1)
    :wxSizer.remove(panels.sizer1, idx)
    :wxWindow.reparent(gauge, panels.page2)
    
    flags = :wxSizerFlags.new |> :wxSizerFlags.expand |> :wxSizerFlags.border
    :wxBoxSizer.add(panels.sizer2, gauge, flags)
    :wxBoxSizer.add(panels.sizer2, :wxStaticLine.new(panels.page2), flags)
    :wxSizerFlags.destroy(flags)
    
    :wxWindow.fitInside(panels.page1)
    :wxWindow.fitInside(panels.page2)
  end
end
