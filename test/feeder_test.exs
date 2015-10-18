defmodule Feedistiller.Feeder.Test do
  use ExUnit.Case
  doctest Feedistiller.Feeder

  alias Feedistiller.Feeder

  defp feed_file, do: "test/data/feed.xml"

  defp feed do
    %Feeder.Feed{
      author: "Herself",
      id: "channel1",
      image: "http://this.is.dummy/image",
      link: "http://this.is.dummy/",
      language: "en-US",
      title: "The Feed",
      subtitle: "The feed's subtitle",
      summary: "The feed's description",
      updated: %Timex.DateTime{
        day: 17, month: 10, year: 2015,
        hour: 17, minute: 42, second: 42,
        timezone: %Timex.TimezoneInfo{}
      }
    }
  end

  defp item(i) do
    %Feeder.Entry{
      author: "Herself",
      id: "item#{i}",
      title: "Item #{i}",
      subtitle: "Subtitle #{i}",
      summary: "Item #{i}",
      link: "http://this.is.dummy/item/#{i}",
      duration: "180",
      updated: %Timex.DateTime{
        day: 18 - i, month: 10, year: 2015,
        hour: 17, minute: 42, second: 42,
        timezone: %Timex.TimezoneInfo{}
      }
    }
  end

  defp check_channel(channel) do
    assert channel.feed == feed
    assert channel.entries |> Enum.count == 5
    channel.entries
    |> Enum.reduce(1, fn e, i -> 
      assert %{e | enclosure: nil} == item(i)
      i + 1
    end)

    channel.entries |> Enum.each(fn e -> assert e.enclosure end)
  end

  test "parse file" do
    {:ok, channel = %Feeder.Channel{}, ""} = Feeder.file(feed_file)
    check_channel(channel)
  end

  test "parse data" do
    {:ok, channel = %Feeder.Channel{}, ""} = Feeder.stream(File.read!(feed_file))
    check_channel(channel)
  end

  test "parse data partial" do
    data = File.read!(feed_file)
    data = String.split_at(data, div(String.length(data), 2))

    opts = [
      continuation_fun: fn
        [] -> {"", []}
        [h | t] -> {h, t}
      end,
      continuation_state: Tuple.to_list(data)
    ]

    {:ok, channel = %Feeder.Channel{}, ""} = Feeder.stream(opts)
    check_channel(channel)
  end
end
