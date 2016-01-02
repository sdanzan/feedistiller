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
  alias Feedistiller.GUI

  @red {255, 0, 0}
  @blue {0, 0, 255}
  @green {0, 255, 0}
  @yellow {255, 255, 0}

  defstruct wx: nil, frame: nil,
            data: %{current: 0, total: 0, total_bytes: 0, finished: 0, complete: false, time: nil},
            feeds: %{page: nil, sizer: nil, f: HashDict.new()},
            items: %{page: nil, sizer: nil, i: HashDict.new()}

  defp hrbytes(bytes) do
    case div(bytes, 1024*1024) do
      0 -> "#{div(bytes, 1024)}K"
      n -> "#{n}M"
    end
  end

  defp percent(_, e) when not is_integer(e), do: "?"
  defp percent(current, expected), do: div(current * 100, expected)

  defp listen(pid, stream) do
    for event <- stream, do: GenServer.cast(pid, event)
  end

  defp set_status_text(f, data) do
    if data.complete do
      :wxFrame.setStatusText(f, String.to_char_list(
        "Downloaded: #{data.total} - Downloading: finished - Bytes: #{data.total_bytes} (#{hrbytes(data.total_bytes)}) - Finished: #{data.finished} - Time: #{tformat(data.time)}"))
    else
      :wxFrame.setStatusText(f, String.to_char_list(
        "Downloaded: #{data.total} - Downloading: #{data.current} - Bytes: #{data.total_bytes} (#{hrbytes(data.total_bytes)}) - Finished: #{data.finished}"))
    end
  end

  defp set_header_text(feed, info) do
    s = "#{feed.name}"
    if info.channel do
      s = s <> " (\"#{info.channel.title}\")"
    end
    s = s <> "\nDestination: #{Path.join(feed.destination, feed.name)}\nDownloaded: #{info.total}"
    if info.complete do
      s = s <> "\nDownloading: finished (time: #{tformat(info.time)})"
      :wxStaticText.setBackgroundColour(info.header, @green)
    else
      s = s <> "\nDownloading: #{info.current}"
    end
    s = s <> "\nBytes: #{info.bytes} (#{hrbytes(info.bytes)})#{}"
    :wxStaticText.setLabel(info.header, String.to_char_list(s))
  end

  defp panel(t) do
    p = :wxScrolledWindow.new(t)
    :wxScrolledWindow.setScrollRate(p, 5, 5)
    s = :wxBoxSizer.new(:wx_const.wx_vertical)
    :wxScrolledWindow.setSizer(p, s)
    {p, s}
  end

  def init({parent, stream}) do
    w = :wx.new()
    f = :wxFrame.new(w, -1, 'Feedistiller - running', [size: {600, 371}])
    pid = self
    :wxFrame.connect(f, :close_window, [callback: fn (_, _) -> GenServer.cast(pid, {:close, parent}) end]) 
    :wxFrame.createStatusBar(f)
    set_status_text(f, %{current: 0, total: 0, total_bytes: 0, finished: 0, complete: false, time: nil})
    t = :wxNotebook.new(f, -1)

    {p1, s1} = panel(t)
    true = :wxNotebook.addPage(t, p1, 'Feeds')

    {p2, s2} = panel(t)
    true = :wxNotebook.addPage(t, p2, 'Files')

    :wxFrame.show(f)

    spawn_link(fn -> listen(pid, stream) end)
    {:ok, %GUI{wx: w, frame: f,
        feeds: %{page: p1, sizer: s1, f: HashDict.new()},
        items: %{page: p2, sizer: s2, i: HashDict.new()}
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
          f: HashDict.put(state.feeds.f, event.feed.name, info)
        }
      }
    }
  end

  # Got a complete channel
  def handle_cast(event = %Event{event: {:channel_complete, channel}}, state = %GUI{}) do
    info = %{HashDict.fetch!(state.feeds.f, event.feed.name) | channel: channel}
    set_header_text(event.feed, info)
    :wxWindow.fitInside(state.feeds.page)
    {:noreply, %GUI{ state |
        feeds: %{ state.feeds |
          f: HashDict.put(state.feeds.f, event.feed.name, info)
        }
      }
    }
  end

  # A feed finished downloading enclosures
  def handle_cast(event = %Event{event: {:end_enclosures, time}}, state = %GUI{}) do
    state = %GUI{state | data: %{state.data | finished: state.data.finished + 1}}
    set_status_text(state.frame, state.data)
    info = %{HashDict.fetch!(state.feeds.f, event.feed.name) | complete: true, time: time}
    set_header_text(event.feed, info)
    :wxWindow.fitInside(state.feeds.page)
    {:noreply, %GUI{ state |
        feeds: %{ state.feeds |
          f: HashDict.put(state.feeds.f, event.feed.name, info)
        }
      }
    }
  end

  # Begin downloading an enclosure
  def handle_cast(event = %Event{event: {:begin, filename}}, state = %GUI{}) do
    # Update global feedback
    info = HashDict.fetch!(state.feeds.f, event.feed.name)
    info = %{info | current: info.current + 1}
    set_header_text(event.feed, info)

    # Add gauge for the new file
    inpanel = :wxPanel.new(state.items.page)
    insizer = :wxBoxSizer.new(:wx_const.wx_vertical)
    :wxPanel.setSizer(inpanel, insizer)
    name = event.feed.name <> " - " <> dformat(event.entry.updated) <> ": " <> event.entry.title
    :wxBoxSizer.add(insizer, :wxStaticText.new(inpanel, -1, String.to_char_list(name)))
    gauge = :wxGauge.new(inpanel, -1, event.entry.enclosure.size)
    flags = :wxSizerFlags.new |> :wxSizerFlags.expand
    :wxBoxSizer.add(insizer, gauge, flags)
    bytes = :wxStaticText.new(inpanel, -1, 'Bytes: 0')
    :wxBoxSizer.add(insizer, bytes)
    flags = flags |> :wxSizerFlags.border
    if Enum.count(state.items.i) > 0 do
      :wxBoxSizer.add(state.items.sizer, :wxStaticLine.new(state.items.page), flags)
    end
    :wxBoxSizer.add(state.items.sizer, inpanel, flags)
    :wxSizerFlags.destroy(flags)

    # Refresh view
    :wxWindow.fitInside(state.items.page)
    h = :wxWindow.getScrollRange(state.items.page, :wx_const.wx_vertical)
    :wxScrolledWindow.scroll(state.items.page, 0, h)
    
    state = %GUI{state |
        data: %{state.data | current: state.data.current + 1},
        feeds: %{state.feeds | f: HashDict.put(state.feeds.f, event.feed.name, info)},
        items: %{state.items | i: HashDict.put(state.items.i, filename, {gauge, bytes, inpanel})}
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
    handle_write(event, filename, written, time, state)
    state = %GUI{state | 
      data: %{state.data | 
        current: state.data.current - 1, total: state.data.total + 1, total_bytes: state.data.total_bytes + written
      }
    }
    set_status_text(state.frame, state.data)
    info = HashDict.fetch!(state.feeds.f, event.feed.name)
    info = %{info | current: info.current - 1, total: info.total + 1, bytes: info.bytes + written}
    set_header_text(event.feed, info)
    {_, _, gaugepanel} = HashDict.fetch!(state.items.i, filename)
    :wxPanel.setBackgroundColour(gaugepanel, @green)
    :wxPanel.refresh(gaugepanel)
    {:noreply, %GUI{state |
        feeds: %{state.feeds |
          f: HashDict.put(state.feeds.f, event.feed.name, info)
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
    info = HashDict.fetch!(state.feeds.f, event.feed.name)
    info = %{info | current: info.current - 1}
    set_header_text(event.feed, info)
    {_, _, gaugepanel} = HashDict.fetch!(state.items.i, filename)
    :wxPanel.setBackgroundColour(gaugepanel, @red)
    :wxPanel.refresh(gaugepanel)
    {:noreply, %GUI{state |
        feeds: %{state.feeds |
          f: HashDict.put(state.feeds.f, event.feed.name, info)
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
    {gauge, bytes, _} = HashDict.fetch!(state.items.i, filename)
    :wxGauge.setValue(gauge, written)
    label = "Bytes: #{written} (#{hrbytes(written)}) - #{percent(written, event.entry.enclosure.size)}%"
    if !is_nil(time), do: label = label <> " - Time: #{tformat(time)}"
    :wxStaticText.setLabel(bytes, String.to_char_list(label))
  end

  defp handle_bad_feed(event, state) do
    info = %{HashDict.fetch!(state.feeds.f, event.feed.name) | complete: true}
    set_header_text(event.feed, info)
    :wxStaticText.setBackgroundColour(info.header, (if info.total > 0, do: @yellow, else: @red))
    :wxStaticText.refresh(info.header)
    {:noreply, %GUI{state |
        feeds: %{state.feeds |
          f: HashDict.put(state.feeds.f, event.feed.name, info)
        }
      }
    }
  end
end
