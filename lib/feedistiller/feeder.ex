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

defmodule Feedistiller.Feeder do
  @moduledoc """
  Elixir encapsulation over the `feeder` module, allowing full usage
  of the stream API. This is a very straightforward encapsulation with
  direct mapping to `feeder` functions and minimal sugar over `feeder`
  records to map them to structs.
  """

  alias Feedistiller.Feeder

  @type ws :: String.t | nil
  @type wd :: DateTime.t | nil
  @type wl :: integer | nil

  defmodule Feed do
    @moduledoc "Mapping to `feeder` `feed` record"
    
    defstruct author: nil, id: nil, image: nil, language: nil, link: nil,
              subtitle: nil, summary: nil, title: nil, updated: nil
    @type t :: %__MODULE__{author: Feeder.ws, id: Feeder.ws, image: Feeder.ws,
                           language: Feeder.ws, link: Feeder.ws, subtitle: Feeder.ws,
                           summary: Feeder.ws, title: Feeder.ws, updated: Feeder.wd}
  end

  defmodule Entry do
    @moduledoc "Mapping to `feeder` `entry` record"

    defstruct author: nil, duration: nil, enclosure: nil, id: nil, image: nil,
              link: nil, subtitle: nil, summary: nil, title: nil, updated: nil
    @type t :: %__MODULE__{author: Feeder.ws, duration: Feeder.wl, enclosure: nil | Feeder.Enclosure.t,
                           id: Feeder.ws, image: Feeder.ws, link: Feeder.ws,
                           subtitle: Feeder.ws, summary: Feeder.ws, title: Feeder.ws,
                           updated: Feeder.wd}
  end

  defmodule Enclosure do
    @moduledoc "Mapping to `feeder` `enclosure` record"

    defstruct url: nil, size: nil, type: nil
    @type t :: %__MODULE__{url: Feeder.ws, size: Feeder.wl, type: Feeder.ws}
  end

  defmodule Channel do
    @moduledoc """
    Holds feed + entries informations. This is used as a default container
    to return feed information when `Feeder.parse/1` is used.
    """

    defstruct feed: %Feeder.Feed{}, entries: []
    @type t :: %__MODULE__{feed: Feeder.Feed.t, entries: list(Feeder.Entry.t)}
  end

  @doc """
  Parse a file. Mapping to `:feeder.file/2` with default options.

  See `xml_sax_parser` documentation for full result type (in case of error, an
  incomplete `Channel` is returned as the last item of the error tuple).
  """
  @spec file(String.t) :: {:ok, Channel.t, String.t } | {term, term, term, term, Channel.t}
  def file(filename) do
    file(filename, default_opts())
  end

  @doc """
  Parse a file. Mapping to `:feeder.file/2`.

  See `xml_sax_parser` documentation for full result type (in case of error, an
  incomplete accumulator is returned as the last item of the error tuple).
  """
  @spec file(String.t, list) :: {:ok, term, String.t } | {term, term, term, term, term}
  def file(filename, opts) do
    :feeder.file(filename, transform_opts(opts))
  end

  @doc """
  Parse some data.
  
  If the input parameter is a string, it will map to `:feeder.stream/2` with default options.
  If it's a prop list, it will map to `:feeder.stream/2` after calling your continuation function
  once to bootstrap the data (curiously `xml_sax_parser` does not do that automatically).

  See `xml_sax_parser` documentation for full result type (in case of error, an
  incomplete `Channel` is returned as the last item of the error tuple).
  """

  @spec stream(String.t | Keyword.t ) :: {:ok, Channel.t, String.t } | {term, term, term, term, Channel.t}

  def stream(opts = [_|_]) do
    {data, state} = opts[:continuation_fun].(opts[:continuation_state])
    stream(data, Keyword.put(opts, :continuation_state, state))
  end

  def stream(<<data :: binary>>) do
    stream(data, default_opts())
  end

  @doc """
  Parse a file. Mapping to `:feeder.stream/2`.

  See `xml_sax_parser` documentation for full result type (in case of error, an
  incomplete accumulator is returned as the last item of the error tuple).
  """
  @spec stream(String.t, Keyword.t) :: {:ok, term, String.t } | {term, term, term, term, term}
  def stream(data, opts) do
    :feeder.stream(data, transform_opts(opts))
  end

  defp transform_opts(opts) do
    if opts[:event_fun] do
      Keyword.put(opts, :event_fun, fn e, acc -> opts[:event_fun].(event(e), acc) end)
    else
      transform_opts(Keyword.merge(default_opts(), opts))
    end
  end

  defp default_opts do
    [
      event_state: %Channel{},
      event_fun: &efun/2
    ]
  end

  defp efun(:endFeed, channel), do: %{channel | entries: :lists.reverse(channel.entries)}
  defp efun(f = %Feed{}, channel), do: %{channel | feed: f}
  defp efun(e = %Entry{}, channel), do: %{channel | entries: [e | channel.entries]}

  defp is_valid_utf8?(<<_ :: utf8, rest :: binary>>), do: is_valid_utf8?(rest)
  defp is_valid_utf8?(<<>>), do: :true
  defp is_valid_utf8?(<<_ :: binary>>), do: :false

  defp to_utf8(<<s :: binary>>) do
    if is_valid_utf8?(s) do
      s
    else
      # Try latin1 and if invalid, truncate
      case :unicode.characters_to_binary(s, :latin1) do
        <<s :: binary>> -> s
        {_, <<s :: binary>>, _} -> s <> "-TRUNCATED"
      end
    end
  end

  defp ws(:undefined), do: nil
  defp ws(any), do: to_utf8(any)
  
  defp wd(:undefined), do: nil
  defp wd(any) do
    case Timex.parse(any, "{RFC1123}") do
      {:error, _} -> nil
      {:ok, date} -> date
    end
  end

  defp wl(:undefined), do: nil
  defp wl(any) do
    try do
      String.to_integer(any)
    rescue
      _ -> nil
    end
  end

  defp event(:endFeed), do: :endFeed

  defp event({:feed, {:feed, author, id, image, language, link, subtitle, summary, title, updated, _url}}) do
    %Feeder.Feed{author: ws(author), id: ws(id), image: ws(image), language: ws(language),
                 link: ws(link), subtitle: ws(subtitle), summary: ws(summary),
                 title: ws(title), updated: wd(updated)}
  end

  defp event({:entry, {:entry, author, _category, duration, encl, id, image, link, subtitle, summary, title, updated}}) do
    %Feeder.Entry{author: ws(author), duration: ws(duration), enclosure: enclosure(encl), id: ws(id),
                  image: ws(image), link: ws(link), subtitle: ws(subtitle), summary: ws(summary),
                  title: ws(title), updated: wd(updated)}
  end

  defp enclosure(:undefined), do: nil
  defp enclosure({:enclosure, url, size, type}) do
    %Feeder.Enclosure{url: ws(url), size: wl(size), type: ws(type)}
  end
end

