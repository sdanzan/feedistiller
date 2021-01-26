defmodule Feedistiller.Test do
  use ExUnit.Case, async: false
  import Mock
  doctest Feedistiller

  alias Feedistiller.FeedAttributes
  alias Feedistiller.Filters
  alias Feedistiller.Limits
  alias Feedistiller.Reporter.Reported

  defp get_feed_data do
    File.read!("test/data/feed.xml")
  end

  defp get_txt_enclosure do
    File.read!("test/data/enclosure.txt")
  end

  defp get_xml_enclosure do
    File.read!("test/data/enclosure.xml")
  end

  defp reset_reported do
    Agent.update(Reported, fn _ -> %{errors: 0, download: 0, total_bytes: 0, download_successful: 0} end)
  end

  defmacrop with_HTTPoison_mock(do: block) do
    quote do
      with_mock HTTPoison, [get!: fn
          ("feed_url", _, _) ->
            {p1, p2} = String.split_at(get_feed_data(), 1350)
            send(self(), %HTTPoison.AsyncChunk{chunk: p1})
            send(self(), %HTTPoison.AsyncChunk{chunk: p2})
            send(self(), %HTTPoison.AsyncEnd{})
          ("enclosure.txt", _, _) ->
            send(self(), %HTTPoison.AsyncChunk{chunk: get_txt_enclosure()})
            send(self(), %HTTPoison.AsyncEnd{})
          ("enclosure.xml", _, _) ->
            send(self(), %HTTPoison.AsyncChunk{chunk: get_xml_enclosure()})
            send(self(), %HTTPoison.AsyncEnd{})
        end] do
        unquote(block)
      end
    end
  end

  setup do
    reset_reported()
    on_exit(nil, fn -> 
      File.rm_rf!("tmp")
    end)
  end

  test "filters, max" do
    with_HTTPoison_mock do
      feed = %FeedAttributes{
        url: "feed_url",
        destination: "tmp",
        name: "test",
        dir: "test",
        filters: %Filters{limits: %Limits{max: 2}}
      }

      :ok = Feedistiller.download_feed(feed)
      assert File.read!("tmp/test/Item 1.txt") == File.read!("test/data/enclosure.txt")
      assert File.read!("tmp/test/Item 2.txt") == File.read!("test/data/enclosure.txt")
      refute File.exists?("tmp/test/Item 3.txt")
      refute File.exists?("tmp/test/Item 4.xml")
      refute File.exists?("tmp/test/Item 5.xml")
    end
  end

  test "filters, only new" do
    with_HTTPoison_mock do
      feed = %FeedAttributes{
        url: "feed_url",
        destination: "tmp",
        name: "test",
        dir: "test",
        filters: %Filters{limits: %Limits{max: 1}},
        only_new: true
      }

      :ok = Feedistiller.download_feed(feed)
      assert File.read!("tmp/test/Item 1.txt") == File.read!("test/data/enclosure.txt")
      refute File.exists?("tmp/test/Item 2.txt")
      refute File.exists?("tmp/test/Item 3.txt")
      refute File.exists?("tmp/test/Item 4.xml")
      refute File.exists?("tmp/test/Item 5.xml")

      :ok = Feedistiller.download_feed(feed)
      assert File.read!("tmp/test/Item 1.txt") == File.read!("test/data/enclosure.txt")
      assert File.read!("tmp/test/Item 2.txt") == File.read!("test/data/enclosure.txt")
      refute File.exists?("tmp/test/Item 3.txt")
      refute File.exists?("tmp/test/Item 4.xml")
      refute File.exists?("tmp/test/IIem 5.xml")
    end
  end

  test "filters, dates" do
    with_HTTPoison_mock do
      feed = %FeedAttributes{
        url: "feed_url",
        destination: "tmp",
        name: "test",
        dir: "test",
        filters: %Filters{
          limits: %Limits{
            max: 2,
            from: Timex.parse!("Wed, 14 Oct 2015 17:42:42 GMT", "{RFC1123}"),
            to: Timex.parse!("Wed, 16 Oct 2015 17:42:42 GMT", "{RFC1123}")
          }
        }
      }

      :ok = Feedistiller.download_feed(feed)
      refute File.exists?("tmp/test/Item 1.txt")
      assert File.read!("tmp/test/Item 2.txt") == File.read!("test/data/enclosure.txt")
      assert File.read!("tmp/test/Item 3.txt") == File.read!("test/data/enclosure.txt")
      refute File.exists?("tmp/test/Item 4.xml")
      refute File.exists?("tmp/test/Item 5.xml")
    end
  end

  test "filters, name" do
    with_HTTPoison_mock do
      feed = %FeedAttributes{
        url: "feed_url",
        destination: "tmp",
        name: "test",
        dir: "test",
        filters: %Filters{name: [~r/Item 1|Item 4/]}
      }

      :ok = Feedistiller.download_feed(feed)
      assert File.read!("tmp/test/Item 1.txt") == File.read!("test/data/enclosure.txt")
      refute File.exists?("tmp/test/Item 2.txt")
      refute File.exists?("tmp/test/Item 3.txt")
      assert File.read!("tmp/test/Item 4.xml") == File.read!("test/data/enclosure.xml")
      refute File.exists?("tmp/test/Item 5.xml")
    end
  end

  test "filters, content" do
    with_HTTPoison_mock do
      feed = %FeedAttributes{
        url: "feed_url",
        destination: "tmp",
        name: "test",
        dir: "test",
        filters: %Filters{mime: [~r/xml/]}
      }

      :ok = Feedistiller.download_feed(feed)
      refute File.exists?("tmp/test/Item 1.txt")
      refute File.exists?("tmp/test/Item 2.txt")
      refute File.exists?("tmp/test/Item 3.txt")
      assert File.read!("tmp/test/Item 4.xml") == File.read!("test/data/enclosure.xml")
      assert File.read!("tmp/test/Item 5.xml") == File.read!("test/data/enclosure.xml")
    end
  end

  test "download feed" do
    with_HTTPoison_mock do
      feed = %FeedAttributes{
        url: "feed_url",
        destination: "tmp",
        dir: "test",
        name: "test"
      }

      :ok = Feedistiller.download_feed(feed)
      assert File.read!("tmp/test/Item 1.txt") == File.read!("test/data/enclosure.txt")
      assert File.read!("tmp/test/Item 2.txt") == File.read!("test/data/enclosure.txt")
      assert File.read!("tmp/test/Item 3.txt") == File.read!("test/data/enclosure.txt")
      assert File.read!("tmp/test/Item 4.xml") == File.read!("test/data/enclosure.xml")
      assert File.read!("tmp/test/Item 5.xml") == File.read!("test/data/enclosure.xml")

      %{errors: errors,
        download: download,
        total_bytes: total_bytes,
        download_successful: success} = Agent.get(Reported, fn x -> x end)

      assert errors == 1 # size mismatch
      assert download == 5
      assert total_bytes == 22 + 22 + 22 + 65 + 65
      assert success == 5
    end
  end

  test "download feeds/1" do
    with_HTTPoison_mock do
      feeds = [%FeedAttributes{
        url: "feed_url",
        destination: "tmp",
        dir: "test",
        name: "test"
      }]

      :ok = Feedistiller.download_feeds(feeds)
      assert File.read!("tmp/test/Item 1.txt") == File.read!("test/data/enclosure.txt")
      assert File.read!("tmp/test/Item 2.txt") == File.read!("test/data/enclosure.txt")
      assert File.read!("tmp/test/Item 3.txt") == File.read!("test/data/enclosure.txt")
      assert File.read!("tmp/test/Item 4.xml") == File.read!("test/data/enclosure.xml")
      assert File.read!("tmp/test/Item 5.xml") == File.read!("test/data/enclosure.xml")
    end
  end

  test "download feeds/2" do
    with_HTTPoison_mock do
      feeds = [%FeedAttributes{
        url: "feed_url",
        destination: "tmp",
        dir: "test",
        name: "test"
      }]

      :ok = Feedistiller.download_feeds(feeds, 2)
      assert File.read!("tmp/test/Item 1.txt") == File.read!("test/data/enclosure.txt")
      assert File.read!("tmp/test/Item 2.txt") == File.read!("test/data/enclosure.txt")
      assert File.read!("tmp/test/Item 3.txt") == File.read!("test/data/enclosure.txt")
      assert File.read!("tmp/test/Item 4.xml") == File.read!("test/data/enclosure.xml")
      assert File.read!("tmp/test/Item 5.xml") == File.read!("test/data/enclosure.xml")
    end
  end

  test "bad destination" do
    feed = %FeedAttributes{
      url: "feed_url",
      destination: "/kjdsahgfsdhdl",
      dir: "test",
      name: "test",
    }

    assert_raise MatchError, fn -> Feedistiller.download_feed(feed) end
  end
end
