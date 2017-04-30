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

defmodule Feedistiller.CLI do
  @moduledoc """
  Command line interface for Feedistiller.
  """

  import Feedistiller.Util
  alias Feedistiller.FeedAttributes


  @help """
  Download enclosures from a set of RSS/Atom feeds.

  Usage: feedistiller [options]
  
  Options appearing before the first `--feed-url` option will be applied as
  default when not overloaded in following `--feed-url` options.

  --feed-url URL     : feed url to get enclosures from, you may pass as much as
                       'feed-url' options as you want.
  
  --name NAME        : name of the feed. This is used as subdirectory in destination.                     

  --destination DEST : root directory to put downloaded files. they will be put
                       in a subdirectory bearing the feed name.

  --max-download MAX : maximum number of simultaneous downloads for a feed. If
                       put before any `--feed-url` option, it will limit the 
                       total number of download across all feeds instead (this
                       means it can be cumulated with a feed specific 
                       'max-download' option).
  --max MAX          : maximum number of files to download per feed (can be 
                       'unlimited' for no limit)
  --min-date MINDATE : download files from item newer than this date. Date 
                       format must be ISOz or YYYY-MM-DD HH:mm:ss (e.g 
                       "2014-10-28T23:54:12Z" or "2014-10-28 23:54:12").
                       Use 'oldest' for no limit.
  --max-date MAXDATE : download files from item older than this date. Use 
                       'latest' fro no limit.
  --filter-name REG  : only download files from items with names matching the
                       given REG regular expression. 
  --filter-content-type REG : only files with content type matching this regular 
                        expression will be downloaded.
  --user             : user for password protected feeds
  --password         : password for password protected feeds
  --only-new         : only new files are downloaded. Check is only done against
                       the required destination.
  --timeout          : timeout in seconds for the http operations. Default to 60s.
  --gui              : show the graphic interface.
  --clean            : do not download anything, try to remove duplicated files and
                       delete crashed tmp file.
  --group            : following options will be applied to all subsequent feed 
                       definitions, until another --group option is encountered.
  """

  @doc "Entry point"
  @spec main([String.t]) :: :ok
  def main(argv) do
    try do
      case parse_argv(argv) do
        {:help, help_message} ->
          IO.puts(help_message)
        {:feeds, [_, {:feeds, []}], _} ->
          IO.puts(@help)
        {:feeds, feeds, gui} ->
          Feedistiller.Reporter.log_to_stdout
          if gui do
            {:ok, _} = GenServer.start_link(Feedistiller.GUI, {self(), Feedistiller.Reporter.stream})
          end
          {timestamp, _} = Timex.Duration.measure(fn ->
            case feeds[:global].max_simultaneous_downloads do
              :unlimited ->
                Feedistiller.download_feeds(feeds[:feeds])
              max ->
                Feedistiller.download_feeds(feeds[:feeds], max)
            end
          end)
          IO.puts("Finished!")
          report = Agent.get(Feedistiller.Reporter.Reported, fn s -> s end)
          IO.puts("Downloaded files: #{report.download} (#{report.download_successful} successful)")
          IO.puts("Total downloaded bytes: #{report.total_bytes}")
          if report.errors >= 0 do
            IO.puts("Errors: #{report.errors}")
          end
          if report.deleted >= 0 do
            IO.puts("Files deleted: #{report.deleted}")
          end
          IO.puts("Time: #{tformat(timestamp)}")
          if gui do
            GenEvent.ack_notify(Feedistiller.Reporter, %Feedistiller.Event{event: {:complete, timestamp}})
            receive do
              :close -> nil
            end
          end
      end
    rescue
      e ->
        IO.puts(@help)
        {:error, e}
    end
  end
  
  @doc """
  Parse command line options and return a list of `%FeedAttributes{}`.

  Global options are expected to come before any `--feed-url` options and
  are applied to all feeds when not overloaded by being respecified after
  a `--feed-url` option.
  """
  @spec parse_argv([String.t]) :: {:feeds, [global: FeedAttributes.t, feeds: [FeedAttributes.t]]} | {:help, String.t}
  def parse_argv(argv) do
    {parsed, [], []} = OptionParser.parse(argv, strict: switches(), alias: aliases())

    if check_help(parsed) do
      help()
    else
      global_config = %FeedAttributes{max_simultaneous_downloads: :unlimited}
      {options, global_config} = parse_feed_attributes({parsed, global_config})
      feeds = parse_feeds_config(options, global_config, group_attr(global_config), []) |> :lists.reverse
      {:feeds, [global: global_config, feeds: feeds], check_gui(parsed)}
    end
  end

  def help do
    {:help, @help}
  end

  defp group_attr(global) do
    %{global | max_simultaneous_downloads: 3}
  end

  defp check_atom(_, []), do: false
  defp check_atom(atom, [{atom, true} | _]), do: true
  defp check_atom(atom, [_ | options]), do: check_atom(atom, options)

  defp check_help(options) do
    check_atom(:help, options)
  end

  defp check_gui(options) do
    check_atom(:gui, options)
  end

  defp parse_feeds_config([], _, _, feeds), do: feeds

  defp parse_feeds_config([{:group, true} | options], global, _, feeds) do
    {options, group} = parse_feed_attributes({options, group_attr(global)})
    parse_feeds_config(options, global, group, feeds)
  end

  defp parse_feeds_config([{:feed_url, url} | options], global, group, feeds) do
    feed = %{group | url: url}
    {options, feed} = parse_feed_attributes({options, feed})
    parse_feeds_config(options, global, group, [feed | feeds])
  end
  
  defp parse_feed_attributes({[], attr}) do
    {[], attr}
  end

  defp parse_feed_attributes({left_options = [{:group, true} | _], attr}) do
    {left_options, attr}
  end

  defp parse_feed_attributes({left_options = [{:feed_url, _} | _], attr}) do
    {left_options, attr}
  end

  defp parse_feed_attributes({[option | left_options], attr}) do
    attributes = case option do
      {:destination, destination} -> 
        %{attr | destination: Path.expand(destination)}
      {:name, name} ->
        %{attr | name: name}
      {:max_download, max} -> 
        %{attr | max_simultaneous_downloads: String.to_integer(max)}
      {:min_date, date} ->
        %{attr | filters: %{attr.filters | limits: %{attr.filters.limits | from: parse_date(date)}}}
      {:max_date, date} ->
        %{attr | filters: %{attr.filters | limits: %{attr.filters.limits | to: parse_date(date)}}}
      {:max, "unlimited"} ->
        %{attr | filters: %{attr.filters | limits: %{attr.filters.limits | max: :unlimited}}}
      {:max, max} ->
        %{attr | filters: %{attr.filters | limits: %{attr.filters.limits | max: String.to_integer(max)}}}
      {:filter_content_type, filter} ->
        %{attr | filters: %{attr.filters | mime: [Regex.compile!(filter) | attr.filters.mime]}}
      {:filter_name, filter} ->
        %{attr | filters: %{attr.filters | name: [Regex.compile!(filter) | attr.filters.name]}}
      {:user, user} ->
        %{attr | user: user}
      {:password, password} ->
        %{attr | password: password}
      {:clean, clean} ->
        %{attr | clean: clean}
      {:only_new, only_new} ->
        %{attr | only_new: only_new}
      {:timeout, timeout} ->
        %{attr | timeout: timeout}
      _ -> attr
    end
    parse_feed_attributes({left_options, attributes})
  end

  defp parse_date(date) do
    case Timex.parse(date, "{ISOz}") do
      {:ok, date_time} -> date_time
      _ -> case Timex.parse(date, "{YYYY}-{M}-{D} {h24}:{m}:{s}") do
        {:ok, date_time} -> date_time
      end
    end
  end

  defp switches do
    [
      name: :keep,
      destination: :keep,
      feed_url: :keep,
      max_download: :keep,
      min_date: :keep,
      max_date: :keep,
      max: :keep,
      filter_content_type: :keep,
      filter_name: :keep,
      user: :keep,
      password: :keep,
      help: :boolean,
      gui: :boolean,
      clean: [:boolean, :keep],
      only_new: [:boolean, :keep],
      group: [:boolean, :keep],
      timeout: [:integer, :keep],
    ]
  end

  defp aliases do
    [
      d: :destination,
      f: :feed_url,
      s: :max_download,
      m: :min_date,
      M: :max_date,
      c: :filter_content_type,
      N: :filter_name,
      n: :name,
      u: :user,
      p: :password,
      h: :help
    ]
  end
end
