defmodule Feedistiller.Limits do
  defstruct from: :oldest, to: :latest, max: :unlimited
  @type t :: %__MODULE__{from: Timex.DateTime | :oldest, to: Timex.DateTime | :latest, max: integer | :unlimited}
end

defmodule Feedistiller.Filters do
  defstruct limits: %Feedistiller.Limits{}, mime: [], name: []
  @type t :: %__MODULE__{limits: Feedistiller.Limits.t, mime: List.t, name: List.t}
end

defmodule Feedistiller.FeedAttributes do
  defstruct url: "", filters: %Feedistiller.Filters{}, destination: ".", max_simultaneous_downloads: 3
  @type t :: %__MODULE__{url: String.t, filters: Filters.t, destination: String.t}
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
  
  require Logger
  alias Feedistiller.FeedAttributes
  alias Feedistiller.Http
  alias Alambic.Semaphore
  alias Alambic.CountDown

  @doc "Download a set of feeds according to their settings."
  @spec download_feeds(list(FeedAttributes.t)) :: :ok
  def download_feeds(feeds) when is_map(feeds) when is_list(feeds)
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
        :ok = File.mkdir_p(destination)

        # Download feed and parse it
        {:ok, feed, _} = FeederEx.parse(Http.full_get!(url))

        # Prepare destination
        destination = Path.join(destination, feed.title)
        :ok = File.mkdir_p(destination)

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
      feedback = "Beginning download for #{entry.title} (url: #{entry.enclosure.url}, size: #{entry.enclosure.size} bytes)"
      filename = Path.join(destination, entry.title <> Path.extname(entry.enclosure.url))
      Logger.info "#{feedback}. Saving file to #{filename}."
      case get_enclosure(filename, entry.enclosure.url, String.to_integer(entry.enclosure.size)) do
        :ok -> Logger.info("#{filename} downloaded succesfully.")
        error -> Logger.error("Error while downloading #{filename} at #{entry.enclosure.url}: #{inspect error}")
      end
      sem_release(gsem)
      sem_release(lsem)
      Alambic.CountDown.signal(countdown)
    end)
  end

  # Fetch an enclosure and save it
  defp get_enclosure(filename, url, size) do
    case File.open(filename, [:write]) do
      {:ok, file} ->
        try do
          {:ok, written} = Http.stream_get!(
            url,
            fn chunk, current_size ->
              :ok = IO.binwrite(file, chunk)
              current_size + byte_size(chunk)
            end,
            0)
          case written do
            ^size -> :ok
            _ -> {:error, {:bad_size, [received: written, expected: size]}}
          end
        rescue
          e -> e
        after
          File.close(file)
        end
      e -> e
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
