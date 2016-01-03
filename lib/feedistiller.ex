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

defmodule Feedistiller.Limits do
  @moduledoc """
  Limits on the number of items to retrieve and the date range of items.

  - `from:` only items newer than this date are retrieved (default is `:oldest` for no limit)
  - `to:` only items older than this date are retrieved (default is `:latest` for not limit)
  - `max:` maximum number of items to retrieve (default is `:unlimited` for no limit) 
  """

  defstruct from: :oldest, to: :latest, max: :unlimited
  @type t :: %__MODULE__{from: Timex.DateTime.t | :oldest, to: Timex.DateTime.t | :latest, max: integer | :unlimited}
end

defmodule Feedistiller.Filters do
  @moduledoc """
  Filters applied to retrieved items.

  - `limits:` a `Limits` struct for date/number limits
  - `mime:` a list of `Regex` applied to the `content-type` of enclosures
  - `name:` a list of Regex applied to the `title` of feed items
  """

  defstruct limits: %Feedistiller.Limits{}, mime: [], name: []
  @type t :: %__MODULE__{limits: Feedistiller.Limits.t, mime: [Regex.t], name: [Regex.t]}
end

defmodule Feedistiller.FeedAttributes do
  @moduledoc """
  The attributes of a feed to download.

  - `url:` web address of the feed
  - `user:` user for protected feed
  - `password:` password for protected feed
  - `destination:` the directory where to put the downloaded items (they will be put in a subdirectory
    with the same name as the feed). Default is `.` (current directory)
  - `max_simultaneous_downloads:` the maximum number of item to download at the same time (default is 3)
  - `filters:` the filters applied to the feed
  - `timeout:` timeout applied to http operations
  """

  defstruct name: "", url: "", filters: %Feedistiller.Filters{},
            destination: ".", max_simultaneous_downloads: 3, user: "", password: "",
            only_new: false, timeout: 60
  @type t :: %__MODULE__{name: String.t, url: String.t, filters: Filters.t, destination: String.t,
                         max_simultaneous_downloads: :unlimited | integer, user: String.t, password: String.t,
                         only_new: boolean, timeout: integer}
end

defmodule Feedistiller.Event do
  @moduledoc """
  Events reported by the downloaders.
  """

  defstruct feed: %Feedistiller.FeedAttributes{}, destination: "", entry: %Feedistiller.Feeder.Entry{}, event: nil
  @type t :: %__MODULE__{feed: Feedistiller.FeedAttributes.t, destination: String.t, entry: Feedistiller.Feeder.Entry.t, event: nil | tuple}
end

defmodule Feedistiller.Util do
  use Timex

  def tformat({m, s, mu})
  when is_integer(m) and is_integer(s) and is_integer(mu)
  do
    TimeFormat.format({m, s, 0}, :humanized)
  end
  def tformat(_), do: ""

  def dformat(date = %DateTime{}), do: DateFormat.format!(date, "%Y-%m-%d", :strftime)
  def dformat(nil), do: "????-??-??"
end

defmodule Feedistiller do
  @moduledoc """
  Provides functions to downloads enclosures of rss/atom feeds.
  
  Features:
  - download multiple feeds at once and limit the number of downloads
    occurring at the same (globally or on per feed basis).
  - various filtering options:
    - content-type criteria
    - item name criteria
    - item date criteria  
  
  `HTTPoison` must be started to use `Feedistiller` functions.
  """
  
  use Timex
  alias Feedistiller.FeedAttributes
  alias Feedistiller.Event
  alias Feedistiller.Http
  alias Feedistiller.Feeder
  alias Alambic.Semaphore
  alias Alambic.CountDown
  alias Alambic.BlockingQueue

  @doc "Download a set of feeds according to their settings."
  @spec download_feeds(list(FeedAttributes.t)) :: :ok
  def download_feeds(feeds) when is_list(feeds)
  do
    download_feeds(feeds, nil)
  end
  
  @doc """
  Download a set of feeds according to their settings, with `max` simultaneous
  downloads at the same time across all feeds.
  """
  @spec download_feeds(list(FeedAttributes.t), integer) :: :ok
  def download_feeds(feeds, max)
  when is_list(feeds) and is_integer(max) and max > 0
  do
    semaphore = Semaphore.create_link(max)
    download_feeds(feeds, semaphore)
    Semaphore.destroy(semaphore)
  end

  @doc """
  Download a set of feeds according to their settings, using the given `semaphore`
  to limit the number of simultaneous downloads.
  """
  @spec download_feeds(list(FeedAttributes.t), Semaphore.t | nil) :: :ok
  def download_feeds(feeds, semaphore)
  when is_list(feeds) and (is_map(semaphore) or is_nil(semaphore))
  do
    feeds 
    |> Enum.map(&Task.async(fn -> download_feed(&1, semaphore) end))
    |> Enum.each(&Task.await(&1, :infinity))
  end
  
  @doc ~S"""
  Download enclosures of the given `feed` according to its settings.
  
  Attributes of the feed are:
  - `url:` the url of the feed. Redirect are auto followed.
  - `destination:` path for the downloaded files. Files are put in a subdirectory
    matching the feed name.
  - `max_simultaneous_downloads:` maximum number of simultaneous downloads for this file.
    Default is `3`. Can be set to `:unlimited` for no limit.
  - `only_new:` donwload only new files (files not already in the destination directory)
  - `filters:` a set of filters to apply to the downloaded files:
    - `limits:` limits on the number of files to download:
      - `to:` download files up to this date (default is `:latest`)
      - `from:` download files from this date (default is `:oldest`)
      - `max:` download at most `max` files (default is `:unlimited`)
    - `mime:` a list of regex to apply to the 'content-type' field of the enclosure. Only
      'content-type' passing those regex are downloaded.
    - `name:` a list of regex to apply to the name of the feed items. Only enclosure attached
      to names matching those regex are downloaded.
  """
  @spec download_feed(FeedAttributes.t, Semaphore.t | nil) :: :ok | {:error, String.t}
  def download_feed(feed = %FeedAttributes{}, global_sem \\ nil)
  when is_map(global_sem) or is_nil(global_sem)
  do
    # Check we can write to destination
    destination = Path.join(feed.destination, feed.name) |> Path.expand
    try do
      :ok = File.mkdir_p(destination)
    rescue
      e ->
        GenEvent.ack_notify(Feedistiller.Reporter, %Event{feed: feed, event: {:error_destination, destination}})
        raise e
    end

    chunksq = BlockingQueue.create(10)
    entriesq = BlockingQueue.create()
    entries = entriesq
    semaphores = [global_sem: global_sem, local_sem: get_sem(feed.max_simultaneous_downloads)]

    # Download feed and gather chunks in a shared queue
    spawn(fn -> generate_chunks_stream(chunksq, feed, semaphores) end)

    # Filters
    titlematch = for regex <- feed.filters.name, do: &Regex.match?(regex, &1.title)
    typematch = for regex <- feed.filters.mime, do: &Regex.match?(regex, &1.enclosure.type)
    filters = typematch ++ titlematch
    filters = [fn e -> !(feed.only_new and File.exists?(filename(e, destination))) end | filters]
    filters = [(&filter_feed_entry(&1, {feed.filters.limits.from, feed.filters.limits.to})) | filters]
    filters = [fn e -> !is_nil(e.enclosure) end | filters]

    # Parse the feed and filter/stream it to the entry queue
    spawn(fn -> generate_entries_stream(entriesq, chunksq, feed, filters) end)
    
    # and get all!
    get_enclosures(entries, destination, feed, semaphores)

    # clean up
    BlockingQueue.destroy(chunksq)
    BlockingQueue.destroy(entriesq)
  end

  defp generate_chunks_stream(chunks, feed, semaphores) do
    {t, _} = Time.measure(fn ->
      try do
        acquire(semaphores)
        GenEvent.ack_notify(Feedistiller.Reporter, %Event{feed: feed, event: :begin_feed})
        Http.stream_get!(feed.url,
          fn (chunk, chunks) ->
            :ok = BlockingQueue.enqueue(chunks, chunk)
            chunks
          end,
          chunks, feed.timeout, feed.user, feed.password)
      rescue
        _ -> GenEvent.ack_notify(Feedistiller.Reporter, %Event{feed: feed, event: :bad_url})
      after
        BlockingQueue.complete(chunks)
        release(semaphores)
      end
    end)
    GenEvent.ack_notify(Feedistiller.Reporter, %Event{feed: feed, event: {:end_feed, t}})
  end

  defp match_filters(_, []), do: true
  defp match_filters(e, [filter | filters]) do
    filter.(e) && match_filters(e, filters)
  end

  defp generate_entries_stream(entries, chunks, feed, filters) do
    try do
      max = if feed.filters.limits.max == :unlimited, do: 999999999999, else: feed.filters.limits.max
      Feeder.stream(
        [
          event_state: {entries, 0},
          event_fun: fn
            (entry = %Feeder.Entry{}, {entries, count}) -> 
              if count < max && match_filters(entry, filters) do
                BlockingQueue.enqueue(entries, entry)
                {entries, count + 1}
              else
                {entries, count}
              end
            (channel = %Feeder.Feed{}, state) ->
              GenEvent.ack_notify(Feedistiller.Reporter, %Event{feed: feed, event: {:channel_complete, channel}})
              state
            (_, state) -> state
          end,
          continuation_state: chunks,
          continuation_fun: fn chunks ->
            case BlockingQueue.dequeue(chunks) do
              {:ok, chunk} -> {chunk, chunks}
              state ->
                if state == :error do
                  GenEvent.ack_notify(Feedistiller.Reporter, %Event{feed: feed, event: :bad_feed})
                end
                {"", chunks}
            end
          end
        ])
    rescue
      _ -> GenEvent.ack_notify(Feedistiller.Reporter, %Event{feed: feed, event: :bad_feed})
    after # whatever happens we complete the entry queue
      BlockingQueue.complete(entries)
    end
  end

  # Filter a feed entry according to date limits
  defp filter_feed_entry(entry, dates) do
    case dates do
      {:oldest, :latest} -> true
      {:oldest, to} -> Timex.Date.compare(entry.updated, to) <= 0
      {from, :latest} -> Timex.Date.compare(entry.updated, from) >= 0
      {from, to} -> Timex.Date.compare(entry.updated, to) <= 0 and Timex.Date.compare(entry.updated, from) >= 0
    end
  end

  defmacrop sem_acquire(s) do
    quote do
      if(!is_nil(unquote(s)), do: Alambic.Semaphore.acquire(unquote(s)))
    end
  end
  
  defmacrop sem_release(s) do
    quote do
      if(!is_nil(unquote(s)), do: Alambic.Semaphore.release(unquote(s)))
    end
  end

  defp acquire([global_sem: gsem, local_sem: lsem]) do
    sem_acquire(gsem)
    sem_acquire(lsem)
  end

  defp release([global_sem: gsem, local_sem: lsem]) do
    sem_release(lsem)
    sem_release(gsem)
  end

  defp filename(entry, destination) do
    Path.join(destination, String.replace(entry.title, ~r/\/|\\/, "|") <> Path.extname(entry.enclosure.url))
  end

  # Download one enclosure
  defp get_enclosure(entry, destination, feed, semaphores, countdown) do
    acquire(semaphores)
    CountDown.increase(countdown)
    spawn_link(fn -> 
      filename = filename(entry, destination)
      GenEvent.ack_notify(Feedistiller.Reporter, %Event{feed: feed, destination: destination, entry: entry, event: {:begin, filename}})
      get_enclosure(filename, entry, feed)
      CountDown.signal(countdown)
      release(semaphores)
    end)
  end

  # Fetch an enclosure and save it
  defp get_enclosure(filename, entry, feed) do
    event = %Event{feed: feed, destination: Path.dirname(filename), entry: entry}
    tmp_filename = filename <> ".tmp"
    case File.open(tmp_filename, [:write]) do
      {:ok, file} ->
        try do
          {time, {:ok, {written, _}}} = Time.measure(fn -> Http.stream_get!(
            entry.enclosure.url,
            fn chunk, {current_size, current_number} ->
              :ok = IO.binwrite(file, chunk)
              s = current_size + byte_size(chunk)
              c = current_number + 1
              if rem(c, 10) == 0 do
                GenEvent.ack_notify(Feedistiller.Reporter, %{event | event: {:write, filename, s}})
              end
              {s, c}
            end,
            {0, 0},
            feed.timeout, feed.user, feed.password)
          end)
          File.close(file)
          File.rename(tmp_filename, filename)
          GenEvent.ack_notify(Feedistiller.Reporter, %{event | event: {:finish_write, filename, written, time}})
        rescue
          e -> GenEvent.ack_notify(Feedistiller.Reporter, %{event | event: {:error_write, filename, e}})
          File.close(file)
          File.rm(tmp_filename)
        end
      e -> GenEvent.ack_notify(Feedistiller.Reporter, %{event | event: {:error_write, filename, e}})
    end
  end

  # Retrieve all enclosures
  defp get_enclosures(entries, destination, feed, semaphores) do
    {t, _} = Time.measure(fn ->
      countdown = CountDown.create_link(0)
      # fetch all enclosures, up to 'max' at the same time
      for entry <- entries do
        get_enclosure(entry, destination, feed, semaphores, countdown)
      end
      CountDown.wait(countdown)
      CountDown.destroy(countdown)
    end)
    GenEvent.ack_notify(Feedistiller.Reporter, %Event{feed: feed, event: {:end_enclosures, t}})
  end
  
  defp get_sem(max) do
    case max do
      :unlimited -> nil
      _ -> Alambic.Semaphore.create(max)
    end
  end
end
