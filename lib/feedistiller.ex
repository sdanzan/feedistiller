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
  - `destination:` the directory where to put the downloaded items (they will be put in a subdirectory
    with the same name as the feed). Default is `.` (current directory)
  - `max_simultaneous_downloads:` the maximum number of item to download at the same time (default is 3)
  - `filters:` the filters applied to the feed
  """

  defstruct url: "", filters: %Feedistiller.Filters{}, destination: ".", max_simultaneous_downloads: 3
  @type t :: %__MODULE__{url: String.t, filters: Filters.t, destination: String.t}
end

defmodule Feedistiller.Event do
  @moduledoc """
  Events reported by the downloaders.
  """

  defstruct destination: "", entry: %FeederEx.Entry{}, event: nil
  @type t :: %__MODULE__{destination: String.t, entry: FeederEx.Entry.t, event: nil | tuple}
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
  
  @vsn 1
  
  alias Feedistiller.FeedAttributes
  alias Feedistiller.Event
  alias Feedistiller.Http
  alias Alambic.Semaphore
  alias Alambic.CountDown

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
  def download_feed(feed, global_sem \\ nil)
  when is_map(feed) and (is_map(global_sem) or is_nil(global_sem))
  do
    case feed do
      %FeedAttributes{url: url, filters: filters, destination: destination, max_simultaneous_downloads: max_simultaneous} ->
        # Check we can write to destination
        try do
          :ok = File.mkdir_p(destination)
        rescue
          e ->
            GenEvent.ack_notify(Feedistiller.Reporter, %Event{event: {:error_destination, destination}})
            raise e
        end

        # Download feed and parse it
        feed = try do
          {:ok, feed, _} = FeederEx.parse(Http.full_get!(url))
          feed
        rescue
          e -> 
            GenEvent.ack_notify(Feedistiller.Reporter, %Event{event: {:bad_url, url}})
            raise e
        end

        # Prepare destination
        destination = Path.join(destination, feed.title)
        try do
          :ok = File.mkdir_p(destination)
        rescue
          e -> 
            GenEvent.ack_notify(Feedistiller.Reporter, %Event{event: {:error_destination, destination}})
            raise e
        end

        # Filter feed entries
        entries = feed.entries
                  |> Stream.filter(fn e -> !is_nil(e.enclosure) end)
                  |> Stream.filter(&filter_feed_entry(&1, {filters.limits.from, filters.limits.to}))
        entries = Enum.reduce(filters.mime, entries,
          fn (regex, entries) -> entries |> Stream.filter(&Regex.match?(regex, &1.enclosure.type)) end)
        entries = Enum.reduce(filters.name, entries,
          fn (regex, entries) -> entries |> Stream.filter(&Regex.match?(regex, &1.title)) end)
        if filters.limits.max != :unlimited do
          entries = entries |> Stream.take(filters.limits.max)
        end
        
        # and get all!
        get_enclosures(entries, destination, global_sem, max_simultaneous)

      _ ->
        {:error, "Feedistiller.FeedAttributes parameter expected"}
    end
  end

  # Filter a feed entry according to date limits
  defp filter_feed_entry(entry, dates) do
    entry_date = entry.updated |> Timex.DateFormat.parse("{RFC1123}")
    case dates do
      {:oldest, :latest} -> true
      {:oldest, to} -> Timex.Date.compare(entry_date, to) <= 0
      {from, :latest} -> Timex.Date.compare(entry_date, from) >= 0
      {from, to} -> Timex.Date.compare(entry_date, to) <= 0 and Timex.Date.compare(entry_date, from) >= 0
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

  # Download one enclosure
  defp get_enclosure(entry, destination, gsem, lsem, countdown) do
    sem_acquire(gsem)
    spawn_link(fn () -> 
      filename = Path.join(destination, entry.title <> Path.extname(entry.enclosure.url))
      GenEvent.ack_notify(Feedistiller.Reporter, %Feedistiller.Event{destination: destination, entry: entry, event: {:begin, filename}})
      get_enclosure(filename, entry)
      sem_release(gsem)
      sem_release(lsem)
      Alambic.CountDown.signal(countdown)
    end)
  end

  # Fetch an enclosure and save it
  defp get_enclosure(filename, entry) do
    event = %Event{destination: Path.dirname(filename), entry: entry}
    case File.open(filename, [:write]) do
      {:ok, file} ->
        try do
          {:ok, written} = Http.stream_get!(
            entry.enclosure.url,
            fn chunk, current_size ->
              :ok = IO.binwrite(file, chunk)
              s = current_size + byte_size(chunk)
              GenEvent.ack_notify(Feedistiller.Reporter, %{event | event: {:write, filename, s}})
              s
            end,
            0)
          GenEvent.ack_notify(Feedistiller.Reporter, %{event | event: {:finish_write, filename, written}})
        rescue
          e -> GenEvent.ack_notify(Feedistiller.Reporter, %{event | event: {:error_write, filename, 0, e}})
        after
          File.close(file)
        end
      e -> GenEvent.ack_notify(Feedistiller.Reporter, %{event | event: {:error_write, filename, 0, e}})
    end
  end

  # Retrieve all enclosures
  defp get_enclosures(entries, destination, gsem, max) do
    max_sem = get_sem(max)
    countdown = CountDown.create_link(0)
	  entries |> Enum.each(# fetch all enclosures, up to 'max' at the same time
            fn entry ->
              sem_acquire(max_sem)
              CountDown.increase(countdown)
              get_enclosure(entry, destination, gsem, max_sem, countdown)
            end)      
    CountDown.wait(countdown)
    clean(max_sem, countdown)
  end
  
  defp get_sem(max) do
    case max do
      :unlimited -> nil
      _ -> Alambic.Semaphore.create(max)
    end
  end
  
  defp clean(sem, cd) do
    if !is_nil(sem), do: Alambic.Semaphore.destroy(sem)
    Alambic.CountDown.destroy(cd)
  end
end
