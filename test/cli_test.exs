defmodule Feedistiller.CLI.Test do
  use ExUnit.Case
  doctest Feedistiller.CLI
  
  alias Feedistiller.CLI 

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
    options = [ "--max-download", "14", "--destination", "destination", "--max", "15",
                "--feed-url", "url-1", "--max", "3", "--max-download", "2", "--user", "Bilbo", "--password", "SauronSux", 
                "--feed-url", "url-2", "--destination", "destination-2", "--filter-content-type", "^audio", "--max", "unlimited",
                "--feed-url", "url-3", "--filter-name", "foo", "--min-date", "2015-12-12 12:12:12", "--filter-name", "bar", "--max-date", "2015-12-13 13:13:13",
              ]

    {:feeds, [global: g, feeds: feeds]} = CLI.parse_argv(options)

    assert g.destination == Path.expand("destination")
    assert g.max_simultaneous_downloads == 14
    assert g.url == ""
    assert g.user == ""
    assert g.password == ""
    
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

    assert f2.url == "url-2"
    assert f2.destination == Path.expand("destination-2")
    assert f2.max_simultaneous_downloads == 3
    assert f2.filters.limits.max == :unlimited
    assert f2.filters.mime == [~r/^audio/]

    assert f3.url == "url-3"
    assert f3.filters.name == [~r/bar/, ~r/foo/]
    assert f3.filters.limits.max == 15
    assert f3.filters.limits.from == Timex.DateFormat.parse!("2015-12-12 12:12:12", @format)
    assert f3.filters.limits.to == Timex.DateFormat.parse!("2015-12-13 13:13:13", @format)
  end
end
