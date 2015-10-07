# Feedistiller [![Build Status](https://travis-ci.org/sdanzan/feedistiller.svg?branch=master)](https://travis-ci.org/sdanzan/feedistiller)


Provides functions to download enclosures of rss/atom feeds.

## Features:
- download multiple feeds at once and limit the number of downloads
  occurring at the same (globally or on per feed basis).
- various filtering options:
  - content-type criteria
  - item name criteria
  - item date criteria  

## Usage

`mix run feedistiller.exs [OPTIONS]`

Example:
> `mix run feedistiller --destination some_directory --max 15 --max-download 5 \
>                        --filter-content-type "audio/mpeg" --feed-url http://some_feed.rss`

See `mix run feedistiller --help` or `Feedistiller.CLI.help` for more informations.

Feedistiller can be embeded as an application in your projects. Just ensure the 
`feedistiller` application is started. Download functions are located in the
`Feedistiller` module. Reporting is available in the `Feedistiller.Reporter.Reported` Agent.
You can activate console or logger logging via the `Feedistiller.Reporter.log_to_console/log_to_logger`
functions. See the source code for some example.
                          
**TODO**
- More filtering options
- password protected feeds
- tests
- **Note:** escript.build does not currently work due to the way `tzdata` handles
  its embeded data (see: https://github.com/bitwalker/timex/issues/86). You must
  use the `feedistiller.exs` script instead.

`Feedistiller` makes use of `HTTPoison`, `FeederEx` and `Timex`.

## Installation

Add the github repository to your mix dependencies:

  1. Add feedistiller to your list of dependencies in `mix.exs`:

        def deps do
          [{:alambic, git: "https://github.com/sdanzan/feedistiller.git"}]
        end

  2. Ensure feedistiller is started before your application:

        def application do
          [applications: [:feedistiller]]
        end

If [available in Hex](https://hex.pm/docs/publish), the package can be installed as:

  1. Add feedistiller to your list of dependencies in `mix.exs`:

        def deps do
          [{:feedistiller, "~> 0.0.1"}]
        end

  2. Ensure alambic is started before your application:

        def application do
          [applications: [:feedistiller]]
        end
