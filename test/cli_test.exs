defmodule Feedistiller.CLI.Test do
  use ExUnit.Case, async: false
  import Mock

  doctest Feedistiller.CLI
  
  alias Feedistiller.CLI 
  alias Feedistiller.Reporter.Reported

  test "help option gives help" do
    assert {:help, help} = CLI.parse_argv(["--help"])
    assert is_binary(help)

    assert {:help, help} = CLI.parse_argv(["--destination", "dest", "--help"])
    assert is_binary(help)

    assert {:help, help} = CLI.parse_argv(["--feed-url", "url", "--help", "--max", "3"])
    assert is_binary(help)

    catch_error {:help, _} = CLI.parse_argv(["--feed-url", "url", "--max", "3"])
  end

  @format "{YYYY}-{M}-{D} {h24}:{m}:{s}"

  test "parse some options" do
    options = [ "--max-download", "14", "--destination", "destination", "--max", "15", "--name", "ALL", "--timeout", "40",
                "--feed-url", "url-1", "--max", "3", "--max-download", "2", "--user", "Bilbo", "--password", "SauronSux", "--name", "Le super podcast",
                "--feed-url", "url-2", "--destination", "destination-2", "--filter-content-type", "^audio", "--max", "unlimited", "--only-new",
                "--feed-url", "url-3", "--filter-name", "foo", "--min-date", "2015-12-12 12:12:12", "--filter-name", "bar", "--max-date", "2015-12-13 13:13:13",
              ]

    {:feeds, [global: g, feeds: feeds]} = CLI.parse_argv(options)

    assert g.destination == Path.expand("destination")
    assert g.max_simultaneous_downloads == 14
    assert g.url == ""
    assert g.user == ""
    assert g.password == ""
    assert g.name == "ALL"
    refute g.only_new
    assert g.timeout == 40
    
    [f3, f2, f1] = feeds

    assert f1.url == "url-1"
    assert f1.destination == Path.expand("destination")
    assert f1.max_simultaneous_downloads == 2
    assert f1.filters.limits.max == 3
    assert f1.filters.limits.from == :oldest
    assert f1.filters.limits.to == :latest
    assert f1.filters.mime == []
    assert f1.filters.name == []
    assert f1.user == "Bilbo"
    assert f1.password == "SauronSux"
    assert f1.name == "Le super podcast"
    refute f1.only_new
    assert f1.timeout == 40

    assert f2.url == "url-2"
    assert f2.destination == Path.expand("destination-2")
    assert f2.max_simultaneous_downloads == 3
    assert f2.filters.limits.max == :unlimited
    assert f2.filters.mime == [~r/^audio/]
    assert f2.name == "ALL"
    assert f2.only_new
    assert f2.timeout == 40

    assert f3.url == "url-3"
    assert f3.filters.name == [~r/bar/, ~r/foo/]
    assert f3.filters.limits.max == 15
    assert f3.filters.limits.from == Timex.DateFormat.parse!("2015-12-12 12:12:12", @format)
    assert f3.filters.limits.to == Timex.DateFormat.parse!("2015-12-13 13:13:13", @format)
    refute f3.only_new
    assert f3.timeout == 40
  end

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

  setup do
    reset_reported()
    on_exit(nil, fn -> 
      File.rm_rf!("tmp")
    end)
  end

  test "main" do
    with_mock HTTPoison, [get!: fn
        ("feed_url", _, _) ->
          {p1, p2} = String.split_at(get_feed_data, 1350)
          send(self, %HTTPoison.AsyncChunk{chunk: p1})
          send(self, %HTTPoison.AsyncChunk{chunk: p2})
          send(self, %HTTPoison.AsyncEnd{})
        ("enclosure.txt", _, _) ->
          send(self, %HTTPoison.AsyncChunk{chunk: get_txt_enclosure})
          send(self, %HTTPoison.AsyncEnd{})
        ("enclosure.xml", _, _) ->
          send(self, %HTTPoison.AsyncChunk{chunk: get_xml_enclosure})
          send(self, %HTTPoison.AsyncEnd{})
      end] do

      args = ["--destination", "tmp", "--feed-url", "feed_url", "--name",  "test"]
      output = ExUnit.CaptureIO.capture_io(fn -> CLI.main(args) end)
      assert Regex.match?(~r/Starting download for `Item 1`/, output)
      assert Regex.match?(~r/Starting download for `Item 2`/, output)
      assert Regex.match?(~r/Starting download for `Item 3`/, output)
      assert Regex.match?(~r/Starting download for `Item 4`/, output)
      assert Regex.match?(~r/Starting download for `Item 5`/, output)
      assert Regex.match?(~r/Download finished for `Item 1`/, output)
      assert Regex.match?(~r/Download finished for `Item 2`/, output)
      assert Regex.match?(~r/Download finished for `Item 3`/, output)
      assert Regex.match?(~r/Download finished for `Item 4`/, output)
      assert Regex.match?(~r/Download finished for `Item 5`/, output)
    end
  end
end
